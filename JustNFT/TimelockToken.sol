// SPDX-License-Identifier: MIT

pragma solidity ^0.4.18;

import "./StandardTokenWithFees.sol";

/**
 * @dev Contract module which acts as a timelocked Token. When set as the
 * owner of an `Ownable` smart contract, it enforces a timelock on all
 * `onlyOwner` maintenance operations. This gives time for users of the
 * controlled contract to exit before a potentially dangerous maintenance
 * operation is applied.
 *
 * This contract is a modified version of:
 * https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/governance/TimelockController.sol
 *
 */
contract TimelockToken is StandardTokenWithFees{
    uint256 internal constant _DONE_TIMESTAMP = uint256(1);

    mapping(uint256 => action) public actions;

    uint256 private _minDelay = 60 seconds;

    uint256 public nonce;

    enum RequestType{
        Issue,
        Redeem
    }
    
    struct action {
        uint256 timestamp;
        RequestType requestType;
        uint256 value;
    }
    /**
     * @dev Emitted when a call is scheduled as part of operation `id`.
     */
    event RequestScheduled(uint256 indexed id, RequestType _type, uint256 value,  uint256 availableTime);
    

    /**
     * @dev Emitted when a call is performed as part of operation `id`.
     */
    event RequestExecuted(uint256 indexed id, RequestType _type, uint256 value);


    // Called when new token are issued
    event Issue(uint amount);

    // Called when tokens are redeemed
    event Redeem(uint amount);
    
    /**
     * @dev Emitted when operation `id` is cancelled.
     */
    event Cancelled(uint256 indexed id);

    /**
     * @dev Emitted when the minimum delay for future operations is modified.
     */
    event DelayTimeChange(uint256 oldDuration, uint256 newDuration);
    
    /**
     * @dev Emitted when the minimum delay for future operations is modified.
     */
    // event ExpireTimeChange(uint256 oldDuration, uint256 newDuration);

    /**
     * @dev Initializes the contract with a given `minDelay`.
     */
    constructor() public {
        emit DelayTimeChange(0, 3 days);
    }

    /**
     * @dev Returns whether an id correspond to a registered operation. This
     * includes both Pending, Ready and Done operations.
     */
    function isOperation(uint256 id) public view returns (bool registered) {
        return getTimestamp(id) > 0;
    }

    /**
     * @dev Returns whether an operation is pending or not.
     */
    function isOperationPending(uint256 id) public view returns (bool pending) {
        return getTimestamp(id) > _DONE_TIMESTAMP;
    }

    /**
     * @dev Returns whether an operation is ready or not.
     */
    function isOperationReady(uint256 id) public view returns (bool ready) {
        uint256 timestamp = getTimestamp(id);
        // solhint-disable-next-line not-rely-on-time
        return timestamp > _DONE_TIMESTAMP && timestamp <= block.timestamp;
    }

    /**
     * @dev Returns whether an operation is done or not.
     */
    function isOperationDone(uint256 id) public view returns (bool done) {
        return getTimestamp(id) == _DONE_TIMESTAMP;
    }

    /**
     * @dev Returns the timestamp at with an operation becomes ready (0 for
     * unset operations, 1 for done operations).
     */
    function getTimestamp(uint256 id) public view returns (uint256 timestamp) {
        return actions[id].timestamp;
    }

    /**
     * @dev Returns the minimum delay for an operation to become valid.
     *
     * This value can be changed by executing an operation that calls `updateDelay`.
     */
    function getMinDelay() public view  returns (uint256 duration) {
        return _minDelay;
    }

    /**
     * @dev Schedule an operation.
     *
     * Emits a {RequestScheduled} event.
     *
     */
    function request(RequestType _requestType, uint256 value) internal {
        uint256 id = nonce;
        nonce ++;
        _schedule(id, _requestType, value,  _minDelay);
    }


    /**
     * @dev Schedule an operation that is to becomes valid after a given delay.
     */
    function _schedule(uint256 id, RequestType _type, uint256 value, uint256 delay) private {
        require(!isOperation(id), "TimelockToken: operation already scheduled");
        require(delay >= getMinDelay(), "TimelockToken: insufficient delay");
        // solhint-disable-next-line not-rely-on-time
        uint256 availableTime = block.timestamp + delay;
        actions[id].timestamp = availableTime;
        actions[id].requestType = _type;
        actions[id].value = value;
        emit RequestScheduled(id, _type, value,  availableTime);
    }

    /**
     * @dev Cancel an operation.
     *
     * Requirements:
     *
     * - the caller must have the 'owner' role.
     */
    function cancel(uint256 id) public onlyOwner {
        require(isOperationPending(id), "TimelockToken: operation cannot be cancelled");
        delete actions[id];
        emit Cancelled(id);
    }


    /**
     * @dev Checks before execution of an operation's calls.
     */
    function _beforeCall(uint256 id) private {
        require(isOperation(id), "TimelockToken: operation is not registered");
    }

    /**
     * @dev Checks after execution of an operation's calls.
     */
    function _afterCall(uint256 id) private {
        require(isOperationReady(id), "TimelockToken: operation is not ready");
        actions[id].timestamp = _DONE_TIMESTAMP;
    }


    /**
     * @dev Execute an operation's call.
     */
    function _call(uint256 id, address owner) internal {
        uint256 amount = actions[id].value;
        // solhint-disable-next-line avoid-low-level-calls
        if(actions[id].requestType == RequestType.Issue) {
            balances[owner] = balances[owner].add(amount);
            _totalSupply = _totalSupply.add(amount);
            emit Transfer(address(0), owner, amount);
            emit Issue(amount);
        }
        else if(actions[id].requestType == RequestType.Redeem) {
            _totalSupply = _totalSupply.sub(amount);
            balances[owner] = balances[owner].sub(amount);
            emit Transfer(owner, address(0), amount);
            emit Redeem(amount);
        }
    }
    
    /*
     * Schedule to issue a new amount of tokens
     * these tokens are deposited into the owner address
     *
     * @param _amount Number of tokens to be issued
     * Requirements:
     *
     * - the caller must have the 'owner' role.
     */
    function requestIssue(uint256 amount) public onlyOwner {
        request(RequestType.Issue, amount);
    }
    
    /*
     * Schedule to redeem a new amount of tokens
     * these tokens are deposited into the owner address
     *
     * @param _amount Number of tokens to be redeemed
     * Requirements:
     *
     * - the caller must have the 'owner' role.
     */
    function requestRedeem(uint256 amount) public onlyOwner {
        request(RequestType.Redeem, amount);
    }

    /*
     * execute  a request
     *
     * @param id the target action id of the request
     * Requirements:
     *
     * - the caller must have the 'owner' role.
     */

    function executeRequest(uint256 id) public onlyOwner {
        _beforeCall(id);
        _call(id, msg.sender);
        _afterCall(id);
    }

}