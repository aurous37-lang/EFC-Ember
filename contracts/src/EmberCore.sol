// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./IEmber.sol";
import "./IEmberRecovery.sol";
import "./IERC20Token.sol";

/// @title EmberCore — Reference Implementation of ERC-EMBER (Layer 2)
/// @notice Burn-to-bloom token. The closed-source phase ends when enough tokens
///         have burned. The standard never confiscates balances: on a quorum
///         release with tokens still outstanding, those holders redeem their
///         proportional share of the unearned remainder.
/// @notice Fee-neutral by default. A fee recipient + bps may be set at deploy
///         (capped at 5%) for use by distribution factories.
/// @notice If recovery recipients are configured, one year of complete on-chain
///         project inactivity allows remaining USDC to be routed 90% to a
///         developer treasury and 10% to the commission recipient.
/// @dev    Extracted from ERC-EMBER-v0.3.md. Differences from the spec sketch
///         are compile-correctness only: `override` on public state variables
///         that implement IEmber getters, and an explicit `manifest()` getter
///         (struct auto-getters omit `string` members).
contract EmberCore is IEmber, IEmberRecovery {
    // === Identity ===
    string public name;
    string public symbol;
    uint8 public constant decimals = 0;

    // === Supply ===
    uint256 public immutable override INITIAL_SUPPLY;
    uint256 public override totalBurned;
    uint256 public totalRedeemed;
    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    // === Release mechanics ===
    address public immutable developer;
    address public immutable dApp;
    bytes32 public immutable originalCommitment;
    string public originalEncryptedCID;
    SourceManifest private _manifest;
    SourceUpdate[] public updates;
    string[] public revealedKeys;
    bool public override released;
    bool public override slashed;
    bool public override abandonedRecovered;
    uint256 public override sellOutTimestamp;
    uint256 public override releaseDeadline;
    uint256 public override lastProjectActivity;

    // === Redemption snapshot (set when Ember Phase opens) ===
    uint256 public triggerBurned;
    uint256 public reservedAtTrigger;
    uint256 public redemptionPoolTotal;
    uint256 public redemptionSupplyTotal;
    uint256 public redemptionPaid;

    struct SourceUpdate {
        bytes32 commitment;
        string encryptedCID;
        bytes32 manifestHash;
        uint256 timestamp;
    }

    // === Constants ===
    uint256 public constant RELEASE_QUORUM_BPS = 8_000;
    uint256 public constant RELEASE_TIMEOUT = 730 days;
    uint256 public constant EMBER_WINDOW = 30 days;
    uint256 public constant ABANDONMENT_TIMEOUT = 365 days;
    uint256 public constant RESERVED_PCT = 20;
    uint256 public constant MAX_FEE_BPS = 500;

    // === Economics ===
    IERC20Token public immutable USDC;
    uint256 public immutable basePrice;
    uint256 public immutable slope;
    uint256 public tokensSold;
    uint256 public totalRaised;
    uint256 public devClaimed;

    // === Optional fee (set by factory; zero for direct deployment) ===
    address public immutable feeRecipient;
    uint256 public immutable feeBps;
    uint256 public totalFeesPaid;

    // === Abandoned capital recovery (disabled when both are zero) ===
    address public immutable override recoveryTreasury;
    address public immutable override recoveryCommissionRecipient;

    // === Events (not in IEmber) ===
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event TokensPurchased(address indexed buyer, uint256 amount, uint256 usdcCost, uint256 fee);
    event DevWithdrew(uint256 usdcAmount);
    event FeePaid(uint256 usdcAmount);

    modifier onlyDeveloper() {
        require(msg.sender == developer, "not developer");
        _;
    }

    modifier notAbandoned() {
        require(!abandonedRecovered, "abandoned");
        _;
    }

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _initialSupply,
        address _developer,
        address _dApp,
        bytes32 _originalCommitment,
        string memory _originalEncryptedCID,
        SourceManifest memory _srcManifest,
        address _usdc,
        uint256 _basePrice,
        uint256 _slope,
        address _feeRecipient,
        uint256 _feeBps,
        address _recoveryTreasury,
        address _recoveryCommissionRecipient
    ) {
        require(_initialSupply > 0 && _developer != address(0) && _dApp != address(0), "bad params");
        require(_originalCommitment != bytes32(0), "no commitment");
        require(_usdc != address(0), "no USDC");
        require(_feeBps <= MAX_FEE_BPS, "fee exceeds cap");
        require(_feeBps == 0 || _feeRecipient != address(0), "no fee recipient");
        require(
            (_recoveryTreasury == address(0) && _recoveryCommissionRecipient == address(0))
                || (_recoveryTreasury != address(0) && _recoveryCommissionRecipient != address(0)),
            "bad recovery recipients"
        );
        // Structural validity only. OSI allowlist enforcement, if any, lives in the factory/registry.
        require(bytes(_srcManifest.spdxLicense).length > 0, "no license");
        require(_srcManifest.archiveHash != bytes32(0), "no archive hash");
        require(_basePrice > 0 || _slope > 0, "no price");

        name = _name;
        symbol = _symbol;
        INITIAL_SUPPLY = _initialSupply;
        _totalSupply = _initialSupply;
        _balances[address(this)] = _initialSupply;
        emit Transfer(address(0), address(this), _initialSupply);

        developer = _developer;
        dApp = _dApp;
        originalCommitment = _originalCommitment;
        originalEncryptedCID = _originalEncryptedCID;
        _manifest = _srcManifest;
        USDC = IERC20Token(_usdc);
        basePrice = _basePrice;
        slope = _slope;
        feeRecipient = _feeRecipient;
        feeBps = _feeBps;
        recoveryTreasury = _recoveryTreasury;
        recoveryCommissionRecipient = _recoveryCommissionRecipient;
        lastProjectActivity = block.timestamp;
    }

    // ---------- Manifest getter (explicit; struct auto-getter drops strings) ----------
    function manifest() external view override returns (SourceManifest memory) {
        return _manifest;
    }

    // ---------- Bonding curve ----------
    function quote(uint256 amount) public view returns (uint256) {
        uint256 a = tokensSold;
        uint256 b = a + amount;
        return basePrice * amount + (slope * (b * b - a * a)) / 2;
    }

    function buy(uint256 amount) external override notAbandoned {
        require(amount > 0 && _balances[address(this)] >= amount, "sold out");
        uint256 cost = quote(amount);
        require(USDC.transferFrom(msg.sender, address(this), cost), "USDC pull failed");

        uint256 fee = feeBps > 0 ? (cost * feeBps) / 10_000 : 0;
        uint256 toProject = cost - fee;

        tokensSold += amount;
        totalRaised += toProject;
        totalFeesPaid += fee;

        if (fee > 0) {
            require(USDC.transfer(feeRecipient, fee), "fee xfer failed");
            emit FeePaid(fee);
        }

        _transfer(address(this), msg.sender, amount);
        if (_balances[address(this)] == 0 && sellOutTimestamp == 0) {
            sellOutTimestamp = block.timestamp;
        }
        _touchProjectActivity();
        emit TokensPurchased(msg.sender, amount, cost, fee);
    }

    // ---------- Burn on use ----------
    function useApp(address user, uint256 amount) external override notAbandoned returns (bool) {
        require(msg.sender == dApp, "only dApp");
        require(releaseDeadline == 0, "ember phase: burns frozen");
        require(_balances[user] >= amount && amount > 0, "bad burn");
        _balances[user] -= amount;
        _totalSupply -= amount;
        totalBurned += amount;
        emit Transfer(user, address(0), amount);
        emit TokensBurnedForUse(user, amount, totalBurned);
        _touchProjectActivity();
        if (totalBurned == INITIAL_SUPPLY) {
            _openEmberPhase();
        }
        return true;
    }

    // ---------- Production updates ----------
    function updateSource(bytes32 newCommitment, string calldata newCID, bytes32 newManifestHash)
        external
        onlyDeveloper
        notAbandoned
    {
        require(releaseDeadline == 0, "ember phase: frozen");
        require(newCommitment != bytes32(0), "no commitment");
        require(bytes(newCID).length > 0, "no CID");
        require(newManifestHash != bytes32(0), "no manifest hash");
        updates.push(SourceUpdate(newCommitment, newCID, newManifestHash, block.timestamp));
        _touchProjectActivity();
        emit SourceUpdated(updates.length, newCommitment, newCID);
    }

    // ---------- Dual-path release trigger ----------
    function forceEmberPhase() external override notAbandoned {
        require(releaseDeadline == 0, "already triggered");
        bool fullBurn = totalBurned == INITIAL_SUPPLY;
        bool quorumPath = (totalBurned * 10_000) / INITIAL_SUPPLY >= RELEASE_QUORUM_BPS && sellOutTimestamp != 0
            // 2-year post-sellout timeout; seconds of validator drift are immaterial.
            // forge-lint: disable-next-line(block-timestamp)
            && block.timestamp >= sellOutTimestamp + RELEASE_TIMEOUT;
        require(fullBurn || quorumPath, "neither path met");
        _openEmberPhase();
    }

    // ---------- Open Ember Phase: freeze + snapshot redemption ----------
    function _openEmberPhase() internal {
        triggerBurned = totalBurned;
        releaseDeadline = block.timestamp + EMBER_WINDOW;

        uint256 devEarned = (totalRaised * triggerBurned) / INITIAL_SUPPLY;
        reservedAtTrigger = (devEarned * RESERVED_PCT) / 100;
        redemptionPoolTotal = totalRaised - devEarned;
        redemptionSupplyTotal = _totalSupply; // remaining unburned, user-held tokens
        _touchProjectActivity();

        emit EmberPhase(releaseDeadline);
    }

    // ---------- Source release ----------
    function release(string[] calldata decryptionKeys) external override notAbandoned {
        require(!released && !slashed, "terminal");
        require(releaseDeadline != 0, "ember phase not started");
        require(decryptionKeys.length == updates.length + 1, "key count mismatch");
        require(keccak256(bytes(decryptionKeys[0])) == originalCommitment, "wrong genesis key");
        for (uint256 i = 0; i < updates.length; i++) {
            require(keccak256(bytes(decryptionKeys[i + 1])) == updates[i].commitment, "wrong update key");
        }
        released = true;
        _touchProjectActivity();
        for (uint256 i = 0; i < decryptionKeys.length; i++) {
            revealedKeys.push(decryptionKeys[i]);
        }
        emit SourceReleased(decryptionKeys);
        emit ContractTerminated(totalBurned, block.timestamp);
    }

    // ---------- Redemption (quorum releases) ----------
    function redemptionQuote(uint256 amount) public view override returns (uint256) {
        if (redemptionSupplyTotal == 0) return 0;
        return (redemptionPoolTotal * amount) / redemptionSupplyTotal;
    }

    function redeem(uint256 amount) external override {
        require(releaseDeadline != 0, "ember phase not started");
        require(redemptionSupplyTotal > 0, "no redemption pool");
        require(amount > 0 && _balances[msg.sender] >= amount, "bad amount");
        uint256 payout = redemptionQuote(amount);
        _balances[msg.sender] -= amount;
        _totalSupply -= amount;
        totalRedeemed += amount;
        redemptionPaid += payout;
        _touchProjectActivity();
        emit Transfer(msg.sender, address(0), amount);
        emit Redeemed(msg.sender, amount, payout);
        require(USDC.transfer(msg.sender, payout), "redeem xfer failed");
    }

    function redemptionReserveRemaining() public view returns (uint256) {
        if (redemptionSupplyTotal <= totalRedeemed) return 0;
        return redemptionQuote(redemptionSupplyTotal - totalRedeemed);
    }

    // ---------- Dev vesting ----------
    function devClaimable() public view override returns (uint256) {
        // Burn progress freezes at the trigger once the Ember Phase opens.
        uint256 burned = releaseDeadline == 0 ? totalBurned : triggerBurned;
        uint256 progress = (burned * 1e18) / INITIAL_SUPPLY;
        uint256 unreserved = (totalRaised * progress * (100 - RESERVED_PCT)) / (100 * 1e18);
        uint256 reserved = released ? (totalRaised * progress * RESERVED_PCT) / (100 * 1e18) : 0;
        uint256 vested = unreserved + reserved;
        return vested > devClaimed ? vested - devClaimed : 0;
    }

    function withdrawDev() external override onlyDeveloper notAbandoned {
        uint256 amt = devClaimable();
        require(amt > 0, "nothing");
        devClaimed += amt;
        _touchProjectActivity();
        require(USDC.transfer(developer, amt), "dev xfer failed");
        emit DevWithdrew(amt);
    }

    // ---------- Slash (reserved tranche only) ----------
    function slashReserve() external override notAbandoned {
        require(!released && !slashed, "terminal");
        require(releaseDeadline != 0, "not slashable");
        // 30-day ember window; validator timestamp drift cannot meaningfully shift it.
        // forge-lint: disable-next-line(block-timestamp)
        require(block.timestamp > releaseDeadline, "still in window");
        slashed = true;
        _touchProjectActivity();
        if (reservedAtTrigger > 0) {
            require(USDC.transfer(address(0xdEaD), reservedAtTrigger), "slash xfer failed");
            emit ReserveSlashed(reservedAtTrigger);
        }
        emit ContractTerminated(totalBurned, block.timestamp);
    }

    // ---------- Abandoned capital recovery ----------
    function recoverAbandonedCapital() external override {
        require(!abandonedRecovered, "already recovered");
        require(recoveryTreasury != address(0) && recoveryCommissionRecipient != address(0), "recovery disabled");
        // 1-year inactivity gate; seconds of validator drift are immaterial.
        // forge-lint: disable-next-line(block-timestamp)
        require(block.timestamp > lastProjectActivity + ABANDONMENT_TIMEOUT, "project active");

        uint256 balance = USDC.balanceOf(address(this));
        uint256 protectedRedemptionReserve = redemptionReserveRemaining();
        uint256 recoverable = balance > protectedRedemptionReserve ? balance - protectedRedemptionReserve : 0;
        require(recoverable > 0, "no recoverable capital");

        bool wasTerminated = released || slashed;
        abandonedRecovered = true;
        uint256 commissionAmount = (recoverable * 10) / 100;
        uint256 treasuryAmount = recoverable - commissionAmount;

        require(USDC.transfer(recoveryTreasury, treasuryAmount), "treasury xfer failed");
        require(USDC.transfer(recoveryCommissionRecipient, commissionAmount), "commission xfer failed");
        emit AbandonedCapitalRecovered(treasuryAmount, commissionAmount);
        if (!wasTerminated) {
            emit ContractTerminated(totalBurned, block.timestamp);
        }
    }

    // ---------- View helpers ----------
    function terminated() external view override returns (bool) {
        return released || slashed || abandonedRecovered;
    }

    // ---------- ERC-165 ----------
    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IEmber).interfaceId
            || interfaceId == type(IEmberRecovery).interfaceId;
    }

    function updateCount() external view returns (uint256) {
        return updates.length;
    }

    function revealedKeyCount() external view returns (uint256) {
        return revealedKeys.length;
    }

    // ---------- ERC20 surface ----------
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address a) external view returns (uint256) {
        return _balances[a];
    }

    function allowance(address o, address s) external view returns (uint256) {
        return _allowances[o][s];
    }

    function approve(address s, uint256 v) external returns (bool) {
        _allowances[msg.sender][s] = v;
        emit Approval(msg.sender, s, v);
        return true;
    }

    function transfer(address to, uint256 v) external returns (bool) {
        _transfer(msg.sender, to, v);
        return true;
    }

    function transferFrom(address f, address t, uint256 v) external returns (bool) {
        uint256 a = _allowances[f][msg.sender];
        require(a >= v, "allowance");
        if (a != type(uint256).max) _allowances[f][msg.sender] = a - v;
        _transfer(f, t, v);
        return true;
    }

    function _transfer(address f, address t, uint256 v) internal {
        require(f != address(0) && t != address(0), "zero address");
        require(_balances[f] >= v, "balance");
        unchecked {
            _balances[f] -= v;
            _balances[t] += v;
        }
        emit Transfer(f, t, v);
    }

    function _touchProjectActivity() internal {
        lastProjectActivity = block.timestamp;
    }
}
