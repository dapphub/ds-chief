// Copyright (C) 2017  DappHub, LLC

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity 0.6.7;

import "ds-test/test.sol";
import "ds-auth/auth.sol";

abstract contract Hevm {
    function warp(uint) virtual public;
    function roll(uint) public virtual;
}

/// @notice Simplified DSPause for testing (only core logic)
contract DSPause is DSAuth {

    // --- Math ---
    function addition(uint x, uint y) internal pure returns (uint z) {
        z = x + y;
        require(z >= x, "ds-pause-add-overflow");
    }
    function subtract(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x, "ds-pause-sub-underflow");
    }

    // --- Data ---
    mapping (bytes32 => bool)  public scheduledTransactions;
    mapping (bytes32 => bool)  public scheduledTransactionsDataHashes;
    DSPauseProxy               public proxy;
    uint                       public delay;

    uint256                    public constant EXEC_TIME                = 3 days;
    uint256                    public constant MAX_DELAY                = 28 days;

    // --- Events ---
    event ScheduleTransaction(address sender, address usr, bytes32 codeHash, bytes parameters, uint earliestExecutionTime);
    event AbandonTransaction(address sender, address usr, bytes32 codeHash, bytes parameters, uint earliestExecutionTime);
    event ExecuteTransaction(address sender, address usr, bytes32 codeHash, bytes parameters, uint earliestExecutionTime);

    // --- Init ---
    constructor(uint delay_, address owner_, DSAuthority authority_) public {
        require(delay_ <= MAX_DELAY, "ds-pause-delay-not-within-bounds");
        delay = delay_;
        owner = owner_;
        authority = authority_;
        proxy = new DSPauseProxy();
    }

    // --- Util ---
    function getTransactionDataHash(address usr, bytes32 codeHash, bytes memory parameters, uint earliestExecutionTime)
        public pure
        returns (bytes32)
    {
        return keccak256(abi.encode(usr, codeHash, parameters, earliestExecutionTime));
    }
    function getTransactionDataHash(address usr, bytes32 codeHash, bytes memory parameters)
        public pure
        returns (bytes32)
    {
        return keccak256(abi.encode(usr, codeHash, parameters));
    }

    function getExtCodeHash(address usr)
        internal view
        returns (bytes32 codeHash)
    {
        assembly { codeHash := extcodehash(usr) }
    }

    // --- Operations ---
    function scheduleTransaction(address usr, bytes32 codeHash, bytes memory parameters, uint earliestExecutionTime)
        public auth
    {
        require(!scheduledTransactions[getTransactionDataHash(usr, codeHash, parameters, earliestExecutionTime)], "ds-pause-already-scheduled");
        require(subtract(earliestExecutionTime, now) <= MAX_DELAY, "ds-pause-delay-not-within-bounds");
        require(earliestExecutionTime >= addition(now, delay), "ds-pause-delay-not-respected");
        bytes32 dataHash = getTransactionDataHash(usr, codeHash, parameters);
        require(!scheduledTransactionsDataHashes[dataHash], "ds-pause-cannot-schedule-same-tx-twice");
        scheduledTransactions[getTransactionDataHash(usr, codeHash, parameters, earliestExecutionTime)] = true;
        scheduledTransactionsDataHashes[dataHash] = true;
        emit ScheduleTransaction(msg.sender, usr, codeHash, parameters, earliestExecutionTime);
    }

    function abandonTransaction(address usr, bytes32 codeHash, bytes memory parameters, uint earliestExecutionTime)
        public auth
    {
        require(scheduledTransactions[getTransactionDataHash(usr, codeHash, parameters, earliestExecutionTime)], "ds-pause-unplotted-plan");
        scheduledTransactions[getTransactionDataHash(usr, codeHash, parameters, earliestExecutionTime)] = false;
        scheduledTransactionsDataHashes[getTransactionDataHash(usr, codeHash, parameters)] = false;
        emit AbandonTransaction(msg.sender, usr, codeHash, parameters, earliestExecutionTime);
    }
    function executeTransaction(address usr, bytes32 codeHash, bytes memory parameters, uint earliestExecutionTime)
        public
        returns (bytes memory out)
    {
        require(scheduledTransactions[getTransactionDataHash(usr, codeHash, parameters, earliestExecutionTime)], "ds-pause-unplotted-plan");
        require(getExtCodeHash(usr) == codeHash, "ds-pause-wrong-codehash");
        require(now >= earliestExecutionTime, "ds-pause-premature-exec");
        require(now < addition(earliestExecutionTime, EXEC_TIME), "ds-pause-expired-tx");
        scheduledTransactions[getTransactionDataHash(usr, codeHash, parameters, earliestExecutionTime)] = false;
        scheduledTransactionsDataHashes[getTransactionDataHash(usr, codeHash, parameters)] = false;
        emit ExecuteTransaction(msg.sender, usr, codeHash, parameters, earliestExecutionTime);
        out = proxy.executeTransaction(usr, parameters);
        require(proxy.owner() == address(this), "ds-pause-illegal-storage-change");
    }
}

contract DSPauseProxy {
    address public owner;
    modifier isAuthorized { require(msg.sender == owner, "ds-pause-proxy-unauthorized"); _; }
    constructor() public { owner = msg.sender; }

    function executeTransaction(address usr, bytes memory parameters)
        public isAuthorized
        returns (bytes memory out)
    {
        bool ok;
        (ok, out) = usr.delegatecall(parameters);
        require(ok, "ds-pause-delegatecall-error");
    }
}