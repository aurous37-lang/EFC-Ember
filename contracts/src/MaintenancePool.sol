// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./IERC20Token.sol";

/// @title MaintenancePool — optional post-bloom funding companion (Layer 4)
/// @notice Optional community infrastructure. It has NO authority over source
///         release, burn accounting, dev vesting, or EMBER termination. Its
///         governance model must be declared at deployment.
/// @notice Every outflow and control change is timelocked: the governor queues a
///         proposal, a deploy-time delay elapses, then anyone may execute it.
///         Funding (`tip` / `payForkRoyalty`) stays instant and permissionless.
/// @dev    No guardian/veto by design. The timelock provides visibility and
///         reaction time, not prevention: a compromised single `governor` can
///         still push a draw or governor change through after `timelockDelay`.
///         Deployments wanting prevention should use a Multisig or DAO governor.
/// @dev    Vote modes (ContributorVote, BurnReceiptVote) set `governor` to an
///         external tally contract that decides what to queue; that tally contract
///         is out of scope for this implementation.
contract MaintenancePool {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    enum GovernanceMode {
        Steward,
        Multisig,
        DAO,
        ContributorVote,
        BurnReceiptVote
    }

    enum ProposalType {
        Draw,
        GovernorChange,
        Sunset
    }

    struct Proposal {
        ProposalType ptype;
        address target; // Draw/Sunset: recipient; GovernorChange: new governor
        uint256 amount; // Draw only; ignored otherwise
        uint256 eta; // earliest execution time = queue time + timelockDelay
        bool executed;
        bool canceled;
        string reason;
    }

    // === Config (immutable) ===
    IERC20Token public immutable USDC;
    address public immutable emberToken;
    GovernanceMode public immutable governanceMode;
    uint256 public immutable timelockDelay;

    // === Mutable state ===
    address public governor;
    bool public closed;
    uint256 public lastDrawTimestamp;
    uint256 public proposalCount;
    uint256 private _reentrancyStatus;
    mapping(uint256 => Proposal) public proposals;

    // === Constants ===
    uint256 public constant MIN_TIMELOCK_DELAY = 1 days;
    uint256 public constant MAX_TIMELOCK_DELAY = 30 days;
    uint256 public constant SUNSET_INACTIVITY = 365 days;

    event Tipped(address indexed from, uint256 amount, string memo);
    event ForkRoyalty(address indexed fromFork, uint256 amount);
    event Claimed(address indexed to, uint256 amount, string reason);
    event GovernorChanged(address indexed oldGovernor, address indexed newGovernor);
    event Sunset(address indexed recipient, uint256 amount, string reason);
    event ProposalQueued(
        uint256 indexed id, ProposalType ptype, address target, uint256 amount, uint256 eta, string reason
    );
    event ProposalExecuted(uint256 indexed id);
    event ProposalCanceled(uint256 indexed id);
    event PoolClosed();

    modifier onlyGovernor() {
        require(msg.sender == governor, "not governor");
        _;
    }

    modifier notClosed() {
        require(!closed, "pool closed");
        _;
    }

    modifier nonReentrant() {
        require(_reentrancyStatus != _ENTERED, "reentrant");
        _reentrancyStatus = _ENTERED;
        _;
        _reentrancyStatus = _NOT_ENTERED;
    }

    constructor(address _emberToken, address _governor, address _usdc, GovernanceMode _mode, uint256 _timelockDelay) {
        require(_emberToken != address(0) && _usdc != address(0), "bad params");
        require(_governor != address(0), "no governor");
        require(_timelockDelay >= MIN_TIMELOCK_DELAY && _timelockDelay <= MAX_TIMELOCK_DELAY, "bad delay");
        emberToken = _emberToken;
        USDC = IERC20Token(_usdc);
        governanceMode = _mode;
        governor = _governor;
        timelockDelay = _timelockDelay;
        lastDrawTimestamp = block.timestamp;
        _reentrancyStatus = _NOT_ENTERED;
    }

    // ---------- Funding (instant, permissionless) ----------
    function tip(uint256 amount, string calldata memo) external notClosed nonReentrant {
        require(amount > 0, "zero amount");
        _safeUsdcTransferFrom(msg.sender, address(this), amount);
        emit Tipped(msg.sender, amount, memo);
    }

    function payForkRoyalty(uint256 amount) external notClosed nonReentrant {
        require(amount > 0, "zero amount");
        _safeUsdcTransferFrom(msg.sender, address(this), amount);
        emit ForkRoyalty(msg.sender, amount);
    }

    // ---------- Queue (governor only, timelocked) ----------
    function queueDraw(uint256 amount, address to, string calldata reason)
        external
        onlyGovernor
        notClosed
        returns (uint256 id)
    {
        require(amount > 0, "zero amount");
        require(to != address(0), "zero recipient");
        id = _queue(ProposalType.Draw, to, amount, reason);
    }

    function queueGovernorChange(address newGovernor) external onlyGovernor notClosed returns (uint256 id) {
        require(newGovernor != address(0), "no governor");
        id = _queue(ProposalType.GovernorChange, newGovernor, 0, "");
    }

    function queueSunset(address recipient, string calldata reason)
        external
        onlyGovernor
        notClosed
        returns (uint256 id)
    {
        require(recipient != address(0), "zero recipient");
        require(_sunsetReady(), "still active");
        id = _queue(ProposalType.Sunset, recipient, 0, reason);
    }

    function _queue(ProposalType ptype, address target, uint256 amount, string memory reason)
        internal
        returns (uint256 id)
    {
        id = ++proposalCount;
        uint256 eta = block.timestamp + timelockDelay;
        proposals[id] = Proposal({
            ptype: ptype, target: target, amount: amount, eta: eta, executed: false, canceled: false, reason: reason
        });
        emit ProposalQueued(id, ptype, target, amount, eta, reason);
    }

    // ---------- Execute (permissionless, after eta) ----------
    function execute(uint256 id) external notClosed nonReentrant {
        require(id > 0 && id <= proposalCount, "unknown proposal");
        Proposal storage p = proposals[id];
        require(!p.executed, "executed");
        require(!p.canceled, "canceled");
        // timelock window; seconds of validator drift are immaterial.
        // forge-lint: disable-next-line(block-timestamp)
        require(block.timestamp >= p.eta, "timelock");

        p.executed = true;

        if (p.ptype == ProposalType.Draw) {
            require(USDC.balanceOf(address(this)) >= p.amount, "insufficient");
            lastDrawTimestamp = block.timestamp;
            emit Claimed(p.target, p.amount, p.reason);
            _safeUsdcTransfer(p.target, p.amount);
        } else if (p.ptype == ProposalType.GovernorChange) {
            emit GovernorChanged(governor, p.target);
            governor = p.target;
        } else {
            // Sunset: re-validate inactivity at execution time so a draw during the
            // delay invalidates a stale wind-down.
            require(_sunsetReady(), "still active");
            closed = true;
            uint256 bal = USDC.balanceOf(address(this));
            emit Sunset(p.target, bal, p.reason);
            emit PoolClosed();
            if (bal > 0) {
                _safeUsdcTransfer(p.target, bal);
            }
        }

        emit ProposalExecuted(id);
    }

    function cancel(uint256 id) external onlyGovernor {
        require(id > 0 && id <= proposalCount, "unknown proposal");
        Proposal storage p = proposals[id];
        require(!p.executed, "executed");
        require(!p.canceled, "canceled");
        p.canceled = true;
        emit ProposalCanceled(id);
    }

    function _sunsetReady() internal view returns (bool) {
        // 1-year inactivity gate; seconds of validator drift are immaterial.
        // forge-lint: disable-next-line(block-timestamp)
        return block.timestamp > lastDrawTimestamp + SUNSET_INACTIVITY;
    }

    function _safeUsdcTransfer(address to, uint256 value) internal {
        (bool success, bytes memory data) = address(USDC).call(abi.encodeCall(IERC20Token.transfer, (to, value)));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "USDC transfer failed");
    }

    function _safeUsdcTransferFrom(address from, address to, uint256 value) internal {
        (bool success, bytes memory data) =
            address(USDC).call(abi.encodeCall(IERC20Token.transferFrom, (from, to, value)));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "USDC pull failed");
    }
}
