// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice ERC20 test double that attempts a configured reentrant callback
///         during transfer/transferFrom, then completes the token transfer.
contract ReentrantToken {
    string public name = "Reentrant Token";
    string public symbol = "RNT";
    uint8 public constant decimals = 6;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    address public target;
    bytes public payload;
    bool public attemptedReentry;
    bool public reentrySucceeded;
    bool private _inTransfer;

    event Transfer(address indexed from, address indexed to, uint256 v);
    event Approval(address indexed owner, address indexed spender, uint256 v);

    function setReentry(address target_, bytes calldata payload_) external {
        target = target_;
        payload = payload_;
        attemptedReentry = false;
        reentrySucceeded = false;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address s, uint256 v) external returns (bool) {
        allowance[msg.sender][s] = v;
        emit Approval(msg.sender, s, v);
        return true;
    }

    function transfer(address to, uint256 v) external returns (bool) {
        _attemptReentry();
        _transfer(msg.sender, to, v);
        return true;
    }

    function transferFrom(address f, address t, uint256 v) external returns (bool) {
        uint256 a = allowance[f][msg.sender];
        require(a >= v, "allowance");
        if (a != type(uint256).max) allowance[f][msg.sender] = a - v;
        _attemptReentry();
        _transfer(f, t, v);
        return true;
    }

    function _attemptReentry() internal {
        if (_inTransfer || target == address(0)) return;

        _inTransfer = true;
        attemptedReentry = true;
        (reentrySucceeded,) = target.call(payload);
        _inTransfer = false;
    }

    function _transfer(address f, address t, uint256 v) internal {
        require(balanceOf[f] >= v, "balance");
        unchecked {
            balanceOf[f] -= v;
            balanceOf[t] += v;
        }
        emit Transfer(f, t, v);
    }
}
