// VoteQuorum.t.sol - test for VoteQuorum.sol
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
pragma experimental ABIEncoderV2;

import "ds-test/test.sol";
import "ds-token/delegate.sol";
import "ds-thing/thing.sol";
import {DSDelegateRoles} from "ds-roles/delegate_roles.sol";
import {DSRoles} from "ds-roles/roles.sol";
import {DSPause} from "./mock/DSPauseMock.sol";
import "../GovernorBravo.sol";

abstract contract Hevm {
    function warp(uint) virtual public;
    function roll(uint) public virtual;
}

contract Target {
    mapping (address => uint) public authorizedAccounts;
    function addAuthorization(address usr) public isAuthorized { authorizedAccounts[usr] = 1; }
    function removeAuthorization(address usr) public isAuthorized { authorizedAccounts[usr] = 0; }
    modifier isAuthorized { require(authorizedAccounts[msg.sender] == 1, "target-unauthorized"); _; }

    constructor() public {
        authorizedAccounts[msg.sender] = 1;
    }

    uint public val = 0;
    function set(uint val_) public isAuthorized {
        val = val_;
    }
}

contract SimpleAction {
    function set(Target target, uint value) public {
        target.set(value);
    }
}

contract VoteQuorumUser is DSThing {
    GovernorBravo governor;

    constructor(GovernorBravo governor_) public {
        governor = governor_;
    }

    function doTransferFrom(DSDelegateToken token, address from, address to,
                            uint amount)
        public
        returns (bool)
    {
        return token.transferFrom(from, to, amount);
    }

    function doTransfer(DSDelegateToken token, address to, uint amount)
        public
        returns (bool)
    {
        return token.transfer(to, amount);
    }

    function doApprove(DSDelegateToken token, address recipient, uint amount)
        public
        returns (bool)
    {
        return token.approve(recipient, amount);
    }

    function doAllowance(DSDelegateToken token, address owner, address spender)
        public view
        returns (uint)
    {
        return token.allowance(owner, spender);
    }

    function doDelegate(DSDelegateToken token, address delegatee)
        public
    {
        return token.delegate(delegatee);
    }

    function doPropose(address[] memory targets, bytes[] memory calldatas) public returns (uint) {
        return governor.propose(targets, new uint[](1), new string[](1), calldatas, "test-proposal");
    }

    function doCancel(uint proposalId) public {
        return governor.cancel(proposalId);
    }

    function doQueue(uint proposalId) public {
        return governor.queue(proposalId);
    }

    function doCastVote(uint proposalId, bool support) public {
        return governor.castVote(proposalId, (support) ? 1 : 0 );
    }

    function doExecute(uint proposalId) public {
        return governor.execute(proposalId);
    }
}

contract GovernorBravoTest is DSThing, DSTest {
    Hevm hevm;

    uint256 constant quorum = 10000 ether;
    uint256 constant proposalThreshold = 50000 ether;
    uint256 constant votingPeriod = 5760;
    uint256 constant proposalLifetime = 10000;

    // pause
    uint256 delay = 1 days;

    uint256 constant initialBalance = 1000000 ether;
    uint256 constant uLargeInitialBalance = 35000 ether;
    uint256 constant uMediumInitialBalance = 25000 ether;
    uint256 constant uSmallInitialBalance = 15000 ether;

    GovernorBravo governor;
    DSDelegateToken prot;
    DSPause pause;
    Target govTarget;
    Target pauseTarget;

    // u prefix: user
    VoteQuorumUser uWhale;
    VoteQuorumUser uLarge;
    VoteQuorumUser uLarge2;
    VoteQuorumUser uLarge3;
    VoteQuorumUser uMedium;
    VoteQuorumUser uSmall;

    address[] targets;
    bytes[] calldatas;

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.roll(10);

        DSRoles roles = new DSRoles();
        pause = new DSPause(delay, address(this), roles);

        pauseTarget = new Target();
        pauseTarget.addAuthorization(address(pause.proxy()));
        pauseTarget.removeAuthorization(address(this));

        prot = new DSDelegateToken("PROT", "PROT");
        prot.mint(initialBalance);

        governor = new GovernorBravo(
            address(pause),
            address(prot),
            votingPeriod,
            proposalLifetime,
            proposalThreshold
        );

        govTarget = new Target();
        govTarget.addAuthorization(address(pause.proxy()));
        govTarget.removeAuthorization(address(this));

        roles.setAuthority(DSAuthority(roles));
        roles.setRootUser(address(governor), true);
        roles.setOwner(address(pause.proxy()));

        uWhale = new VoteQuorumUser(governor);
        uLarge = new VoteQuorumUser(governor);
        uLarge2 = new VoteQuorumUser(governor);
        uLarge3 = new VoteQuorumUser(governor);
        uMedium = new VoteQuorumUser(governor);
        uSmall = new VoteQuorumUser(governor);

        assert(uLargeInitialBalance < uMediumInitialBalance + uSmallInitialBalance);

        prot.transfer(address(uWhale), uLargeInitialBalance * 10);
        prot.transfer(address(uLarge), uLargeInitialBalance);
        prot.transfer(address(uLarge2), uLargeInitialBalance);
        prot.transfer(address(uLarge3), uLargeInitialBalance);
        prot.transfer(address(uMedium), uMediumInitialBalance);
        prot.transfer(address(uSmall), uSmallInitialBalance);

        hevm.roll(20);
    }

    function test_initialization2() public {
        assert(address(governor.comp()) == address(prot));
        assert(address(governor.timelock()) == address(pause));
        assert(governor.proposalThreshold() == proposalThreshold);
        assert(governor.votingPeriod() == votingPeriod);
        assert(governor.votingDelay() == proposalLifetime);
    }

    function testFail_propose_not_enough_votes() public {
        targets.push(address(govTarget));
        calldatas.push(bytes(""));

        uLarge.doPropose(targets, calldatas);
    }

    function test_propose() public {
        uSmall.doDelegate(prot, address(uLarge));
        uLarge.doDelegate(prot, address(uLarge));
        hevm.roll(block.number + 1);

        targets.push(address(govTarget));
        calldatas.push(bytes("0xabc"));

        uint proposalId = uLarge.doPropose(targets, calldatas);

        {
            (
                uint id,
                address proposer,
                uint eta,
                uint startBlock,
                uint endBlock,
                uint forVotes,
                uint againstVotes,
                uint abstainVotes,
                bool canceled,
                bool executed
            ) = governor.proposals(proposalId);

            assertEq(id, proposalId);
            assertEq(proposer, address(uLarge));
            assertEq(eta, 0);
            assertEq(startBlock, block.number + proposalLifetime);
            assertEq(endBlock, block.number + proposalLifetime + votingPeriod);
            assertEq(forVotes, 0);
            assertEq(againstVotes, 0);
            assertEq(abstainVotes, 0);
            assertTrue(!canceled);
            assertTrue(!executed);
        }
    }

    function testFail_already_pending_proposal() public {
        uSmall.doDelegate(prot, address(uLarge));
        uLarge.doDelegate(prot, address(uLarge));

        targets.push(address(govTarget));
        calldatas.push(bytes("0xabc"));

        hevm.roll(block.number + 1);
        uLarge.doPropose(targets, calldatas);
        uLarge.doPropose(targets, calldatas);
    }

    function testFail_already_active_proposal() public {
        uSmall.doDelegate(prot, address(uLarge));
        uLarge.doDelegate(prot, address(uLarge));

        targets.push(address(govTarget));
        calldatas.push(bytes("0xabc"));

        hevm.roll(block.number + 1);
        uLarge.doPropose(targets, calldatas);

        hevm.roll(block.number + 1 + votingPeriod);
        uLarge.doPropose(targets, calldatas);
    }

    function  test_execute_schedule_proposal() public {
        uSmall.doDelegate(prot, address(uLarge));
        uMedium.doDelegate(prot, address(uLarge));
        uLarge3.doDelegate(prot, address(uLarge));
        uLarge2.doDelegate(prot, address(uLarge));

        hevm.roll(block.number + 1);

        targets.push(address(new SimpleAction()));
        calldatas.push(abi.encodeWithSelector(SimpleAction.set.selector, pauseTarget, 30));

        uint proposalId = uLarge.doPropose(targets, calldatas);

        hevm.roll(block.number + governor.votingDelay() + votingPeriod); // very last block
        uLarge.doCastVote(proposalId, true);

        hevm.roll(block.number + 1);
        uSmall.doQueue(proposalId);

        hevm.warp(now + pause.delay());
        uMedium.doExecute(proposalId);

        assertEq(pauseTarget.val(), 30);
    }

    function  testFail_queue_didnt_meet_quorum() public {
        uSmall.doDelegate(prot, address(uLarge));
        uLarge3.doDelegate(prot, address(uLarge3));
        uLarge2.doDelegate(prot, address(uLarge2));
        hevm.roll(block.number + 1);

        targets.push(address(new SimpleAction()));
        calldatas.push(abi.encodeWithSelector(SimpleAction.set.selector, pauseTarget, 30));

        uint proposalId = uLarge.doPropose(targets, calldatas);

        hevm.roll(block.number + governor.votingDelay() + votingPeriod); // very last block
        uLarge.doCastVote(proposalId, true);
        uLarge2.doCastVote(proposalId, true);
        uLarge3.doCastVote(proposalId, true);

        hevm.roll(block.number + 1);
        uMedium.doCastVote(proposalId, true); // voting after finish
        uMedium.doExecute(proposalId);
    }

    function  testFail_queue_more_con_votes() public {
        uWhale.doDelegate(prot, address(uWhale));
        uSmall.doDelegate(prot, address(uLarge));
        uLarge.doDelegate(prot, address(uLarge));
        uMedium.doDelegate(prot, address(uMedium));
        uLarge3.doDelegate(prot, address(uLarge3));
        uLarge2.doDelegate(prot, address(uLarge2));

        hevm.roll(block.number + 1);

        targets.push(address(new SimpleAction()));
        calldatas.push(abi.encodeWithSelector(SimpleAction.set.selector, pauseTarget, 30));

        uint proposalId = uLarge.doPropose(targets, calldatas);

        hevm.roll(block.number + governor.votingDelay() + votingPeriod); // very last block
        uMedium.doCastVote(proposalId, true);
        uLarge.doCastVote(proposalId, true);
        uLarge2.doCastVote(proposalId, true);
        uLarge3.doCastVote(proposalId, true);
        uWhale.doCastVote(proposalId, false);

        hevm.roll(block.number + 1);
        uMedium.doQueue(proposalId);
    }

    function  testFail_queue_twice() public {
        uSmall.doDelegate(prot, address(uLarge));
        uLarge.doDelegate(prot, address(uLarge));
        uMedium.doDelegate(prot, address(uLarge));
        uLarge3.doDelegate(prot, address(uLarge));
        uLarge2.doDelegate(prot, address(uLarge));

        hevm.roll(block.number + 1);

        targets.push(address(new SimpleAction()));
        calldatas.push(abi.encodeWithSelector(SimpleAction.set.selector, pauseTarget, 30));

        uint proposalId = uLarge.doPropose(targets, calldatas);

        hevm.roll(block.number + governor.votingDelay() + votingPeriod); // very last block
        uLarge.doCastVote(proposalId, true);

        hevm.roll(block.number + 1);
        uSmall.doQueue(proposalId);
        uWhale.doQueue(proposalId);
    }

    function  test_cancel() public {
        uSmall.doDelegate(prot, address(uLarge));
        uLarge.doDelegate(prot, address(uLarge));
        uMedium.doDelegate(prot, address(uMedium));
        uLarge3.doDelegate(prot, address(uLarge3));
        uLarge2.doDelegate(prot, address(uLarge2));

        hevm.roll(block.number + 1);
        targets.push(address(new SimpleAction()));
        calldatas.push(abi.encodeWithSelector(SimpleAction.set.selector, pauseTarget, 30));

        uint proposalId = uLarge.doPropose(targets, calldatas);
        uSmall.doDelegate(prot, address(uSmall)); // bumping proposer below the threshold

        hevm.roll(block.number + governor.votingDelay() + votingPeriod); // very last block
        uMedium.doCastVote(proposalId, true);
        uLarge.doCastVote(proposalId, true);
        uLarge2.doCastVote(proposalId, true);
        uLarge3.doCastVote(proposalId, true);

        hevm.roll(block.number + 1);
        uSmall.doQueue(proposalId);
        uLarge.doCancel(proposalId);

        (,,,,,,,, bool canceled,) = governor.proposals(proposalId);
        assertTrue(canceled);
    }
}