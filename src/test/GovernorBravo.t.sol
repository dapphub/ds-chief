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
import {DSRoles} from "ds-roles/roles.sol";
import {DSPause} from "./mock/DSPauseMock.sol";
import "../GovernorBravo.sol";
import {DSThing} from 'ds-thing/thing.sol';

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

contract StakingMock {
    uint public descendantPerAncestor = 1 ether;

    function setDescendantPerAncestor(uint val) public {
        descendantPerAncestor = val;
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

contract GovernorProxyActions {
    function setVotingDelay(address governor, uint votingDelay) public {
        GovernorBravo(governor)._setVotingDelay(votingDelay);
    }

    function setVotingPeriod(address governor, uint votingPeriod) public {
        GovernorBravo(governor)._setVotingPeriod(votingPeriod);
    }

    function setProposalThreshold(address governor, uint proposalThreshold) public {
        GovernorBravo(governor)._setProposalThreshold(proposalThreshold);
    }

    function setPendingAdmin(address governor, address who) public {
        GovernorBravo(governor)._setPendingAdmin(who);
    }
}

contract GovernorBravoTest is DSThing, DSTest {
    Hevm hevm;

    uint256 constant quorum = 10000 ether;
    uint256 constant proposalThreshold = 50000 ether;
    uint256 constant votingPeriod = 5760;
    uint256 constant votingDelay = 10000;
    uint256 constant boostMultiplier = 2 ether; // 2x

    // pause
    uint256 delay = 1 days;

    uint256 constant initialBalance = 1000000 ether;
    uint256 constant uLargeInitialBalance = 35000 ether + 1;
    uint256 constant uMediumInitialBalance = 25000 ether + 1;
    uint256 constant uSmallInitialBalance = 15000 ether + 1;

    GovernorBravo governor;
    DSDelegateToken prot;
    DSDelegateToken boost;
    StakingMock staking;
    DSPause pause;
    Target govTarget;
    Target pauseTarget;
    GovernorProxyActions proxyActions;

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

        boost = new DSDelegateToken("BOOST", "BOOST");
        boost.mint(initialBalance);

        staking = new StakingMock();

        governor = new GovernorBravo(
            address(pause),
            address(prot),
            address(boost),
            address(staking),
            boostMultiplier,
            votingPeriod,
            votingDelay,
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

        proxyActions = new GovernorProxyActions();

        hevm.roll(20);
    }

    function test_initialization() public {
        assert(address(governor.governanceToken()) == address(prot));
        assert(address(governor.timelock()) == address(pause));
        assert(governor.proposalThreshold() == proposalThreshold);
        assert(governor.votingPeriod() == votingPeriod);
        assert(governor.votingDelay() == votingDelay);
        assert(governor.admin() == address(pause.proxy()));
    }

    function testFail_deploy_null_pause() public {
        governor = new GovernorBravo(
            address(0),
            address(prot),
            address(boost),
            address(staking),
            boostMultiplier,
            votingPeriod,
            votingDelay,
            proposalThreshold
        );
    }

    function testFail_deploy_null_prot() public {
        governor = new GovernorBravo(
            address(pause),
            address(0),
            address(boost),
            address(staking),
            boostMultiplier,
            votingPeriod,
            votingDelay,
            proposalThreshold
        );
    }

    function testFail_deploy_null_boost() public {
        governor = new GovernorBravo(
            address(pause),
            address(prot),
            address(0),
            address(staking),
            boostMultiplier,
            votingPeriod,
            votingDelay,
            proposalThreshold
        );
    }

    function testFail_deploy_null_staking() public {
        governor = new GovernorBravo(
            address(pause),
            address(prot),
            address(boost),
            address(0),
            boostMultiplier,
            votingPeriod,
            votingDelay,
            proposalThreshold
        );
    }

    function testFail_deploy_invalid_staking() public {
        governor = new GovernorBravo(
            address(pause),
            address(prot),
            address(boost),
            address(0xabc),
            boostMultiplier,
            votingPeriod,
            votingDelay,
            proposalThreshold
        );
    }

    function testFail_deploy_null_boost_multiplier() public {
        governor = new GovernorBravo(
            address(pause),
            address(prot),
            address(boost),
            address(staking),
            0,
            votingPeriod,
            votingDelay,
            proposalThreshold
        );
    }

    function testFail_deploy_invalid_voting_period() public {
        governor = new GovernorBravo(
            address(pause),
            address(prot),
            address(boost),
            address(staking),
            boostMultiplier,
            governor.MIN_VOTING_PERIOD() - 1,
            votingDelay,
            proposalThreshold
        );
    }

    function testFail_deploy_invalid_voting_period2() public {
        governor = new GovernorBravo(
            address(pause),
            address(prot),
            address(boost),
            address(staking),
            boostMultiplier,
            governor.MAX_VOTING_PERIOD() + 1,
            votingDelay,
            proposalThreshold
        );
    }

    function testFail_deploy_invalid_voting_delay() public {
        governor = new GovernorBravo(
            address(pause),
            address(prot),
            address(boost),
            address(staking),
            boostMultiplier,
            votingPeriod,
            governor.MIN_VOTING_DELAY() - 1,
            proposalThreshold
        );
    }

    function testFail_deploy_invalid_voting_delay2() public {
        governor = new GovernorBravo(
            address(pause),
            address(prot),
            address(boost),
            address(staking),
            boostMultiplier,
            votingPeriod,
            governor.MAX_VOTING_DELAY() + 1,
            proposalThreshold
        );
    }

    function testFail_deploy_invalid_threshold() public {
        governor = new GovernorBravo(
            address(pause),
            address(prot),
            address(boost),
            address(staking),
            boostMultiplier,
            votingPeriod,
            votingDelay,
            governor.MIN_PROPOSAL_THRESHOLD() - 1
        );
    }

    function testFail_deploy_invalid_threshold2() public {
        governor = new GovernorBravo(
            address(pause),
            address(prot),
            address(boost),
            address(staking),
            boostMultiplier,
            votingPeriod,
            votingDelay,
            governor.MAX_PROPOSAL_THRESHOLD() + 1
        );
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
            assertEq(startBlock, block.number + votingDelay);
            assertEq(endBlock, block.number + votingDelay + votingPeriod);
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

    function test_execute_schedule_proposal() public {
        uSmall.doDelegate(prot, address(uLarge));
        uMedium.doDelegate(prot, address(uLarge));
        uLarge3.doDelegate(prot, address(uLarge));
        uLarge2.doDelegate(prot, address(uLarge));

        hevm.roll(block.number + 1);

        targets.push(address(new SimpleAction()));
        calldatas.push(abi.encodeWithSelector(SimpleAction.set.selector, pauseTarget, 30));

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
            assertEq(startBlock, block.number + votingDelay);
            assertEq(endBlock, block.number + votingDelay + votingPeriod);
            assertEq(forVotes, 0);
            assertEq(againstVotes, 0);
            assertEq(abstainVotes, 0);
            assertTrue(!canceled);
            assertTrue(!executed);
        }

        hevm.roll(block.number + governor.votingDelay() + votingPeriod); // very last block
        assertEq(uint256(governor.state(proposalId)), 1); // active

        uLarge.doCastVote(proposalId, true);
        hevm.roll(block.number + 1);
        assertEq(uint256(governor.state(proposalId)), 4); // succeeded

        uSmall.doQueue(proposalId);
        assertEq(uint256(governor.state(proposalId)), 5); // queued


        hevm.warp(now + pause.delay());
        uMedium.doExecute(proposalId);
        assertEq(uint256(governor.state(proposalId)), 7); // executed

        {
            (
                ,,,,,,,,
                bool canceled,
                bool executed
            ) = governor.proposals(proposalId);
            assertTrue(!canceled);
            assertTrue(executed);
        }

        assertEq(pauseTarget.val(), 30);
    }

    function test_execute_schedule_proposal_already_executed_in_pause() public {
        uSmall.doDelegate(prot, address(uLarge));
        uMedium.doDelegate(prot, address(uLarge));
        uLarge3.doDelegate(prot, address(uLarge));
        uLarge2.doDelegate(prot, address(uLarge));

        hevm.roll(block.number + 1);

        targets.push(address(new SimpleAction()));
        calldatas.push(abi.encodeWithSelector(SimpleAction.set.selector, pauseTarget, 30));

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
            assertEq(startBlock, block.number + votingDelay);
            assertEq(endBlock, block.number + votingDelay + votingPeriod);
            assertEq(forVotes, 0);
            assertEq(againstVotes, 0);
            assertEq(abstainVotes, 0);
            assertTrue(!canceled);
            assertTrue(!executed);
        }

        hevm.roll(block.number + governor.votingDelay() + votingPeriod); // very last block
        assertEq(uint256(governor.state(proposalId)), 1); // active

        uLarge.doCastVote(proposalId, true);
        hevm.roll(block.number + 1);
        assertEq(uint256(governor.state(proposalId)), 4); // succeeded

        uSmall.doQueue(proposalId);
        uint eta = now + pause.delay();
        assertEq(uint256(governor.state(proposalId)), 5); // queued


        hevm.warp(now + pause.delay());
        address target = targets[0];

        bytes32 codeHash;
        assembly { codeHash := extcodehash(target) }

        // executing directly in pause
        pause.executeTransaction(targets[0], codeHash, calldatas[0], eta);

        uMedium.doExecute(proposalId);
        assertEq(uint256(governor.state(proposalId)), 7); // executed

        {
            (
                ,,,,,,,,
                bool canceled,
                bool executed
            ) = governor.proposals(proposalId);
            assertTrue(!canceled);
            assertTrue(executed);
        }

        assertEq(pauseTarget.val(), 30);
    }

    function testFail_queue_didnt_meet_quorum() public {
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

    function testFail_queue_more_con_votes() public {
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

    function testFail_queue_twice() public {
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

    function test_cancel() public {
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
        assertEq(uint256(governor.state(proposalId)), 2); // cancelled
    }

    function testFail_cancel_already_executed() public {
        uSmall.doDelegate(prot, address(uLarge));
        uMedium.doDelegate(prot, address(uLarge));

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
        uLarge.doCancel(proposalId);
    }

    function testFail_cancel_unauthorized() public {
        uSmall.doDelegate(prot, address(uLarge));
        uLarge.doDelegate(prot, address(uLarge));
        uMedium.doDelegate(prot, address(uMedium));

        hevm.roll(block.number + 1);
        targets.push(address(new SimpleAction()));
        calldatas.push(abi.encodeWithSelector(SimpleAction.set.selector, pauseTarget, 30));

        uint proposalId = uLarge.doPropose(targets, calldatas);

        hevm.roll(block.number + governor.votingDelay() + votingPeriod); // very last block
        uMedium.doCastVote(proposalId, true);
        uLarge.doCastVote(proposalId, true);
        uLarge2.doCastVote(proposalId, true);
        uLarge3.doCastVote(proposalId, true);

        hevm.roll(block.number + 1);
        uSmall.doQueue(proposalId);
        uMedium.doCancel(proposalId);
    }

    function test_get_actions() public {
        uSmall.doDelegate(prot, address(uLarge));
        uLarge.doDelegate(prot, address(uLarge));
        uMedium.doDelegate(prot, address(uMedium));

        hevm.roll(block.number + 1);
        targets.push(address(new SimpleAction()));
        calldatas.push(abi.encodeWithSelector(SimpleAction.set.selector, pauseTarget, 30));

        uint proposalId = uLarge.doPropose(targets, calldatas);

        (address[] memory _targets,,,bytes[] memory _calldatas) = governor.getActions(proposalId);
        assertEq(_targets[0], targets[0]);
        assertEq(keccak256(_calldatas[0]), keccak256(calldatas[0]));
    }

    function test_set_voting_delay() public {
        uSmall.doDelegate(prot, address(uLarge));
        uMedium.doDelegate(prot, address(uLarge));
        uLarge3.doDelegate(prot, address(uLarge));
        uLarge2.doDelegate(prot, address(uLarge));

        hevm.roll(block.number + 1);

        targets.push(address(proxyActions));
        calldatas.push(abi.encodeWithSelector(proxyActions.setVotingDelay.selector, address(governor), votingDelay + 50));

        uint proposalId = uLarge.doPropose(targets, calldatas);

        hevm.roll(block.number + governor.votingDelay() + votingPeriod); // very last block
        uLarge.doCastVote(proposalId, true);

        hevm.roll(block.number + 1);
        uSmall.doQueue(proposalId);

        hevm.warp(now + pause.delay());
        uMedium.doExecute(proposalId);

        assertEq(governor.votingDelay(), votingDelay + 50);
    }

    function testFail_set_voting_delay_unauthorized() public {
        governor._setVotingDelay(votingDelay + 1);
    }

    function testFail_set_voting_delay_invalid() public {
        uSmall.doDelegate(prot, address(uLarge));
        uMedium.doDelegate(prot, address(uLarge));
        uLarge3.doDelegate(prot, address(uLarge));
        uLarge2.doDelegate(prot, address(uLarge));

        hevm.roll(block.number + 1);

        targets.push(address(proxyActions));
        calldatas.push(abi.encodeWithSelector(proxyActions.setVotingDelay.selector, address(governor), governor.MAX_VOTING_DELAY() + 1));

        uint proposalId = uLarge.doPropose(targets, calldatas);

        hevm.roll(block.number + governor.votingDelay() + votingPeriod); // very last block
        uLarge.doCastVote(proposalId, true);

        hevm.roll(block.number + 1);
        uSmall.doQueue(proposalId);

        hevm.warp(now + pause.delay());
        uMedium.doExecute(proposalId);
    }

    function testFail_set_voting_delay_invalid2() public {
        uSmall.doDelegate(prot, address(uLarge));
        uMedium.doDelegate(prot, address(uLarge));
        uLarge3.doDelegate(prot, address(uLarge));
        uLarge2.doDelegate(prot, address(uLarge));

        hevm.roll(block.number + 1);

        targets.push(address(proxyActions));
        calldatas.push(abi.encodeWithSelector(proxyActions.setVotingDelay.selector, address(governor), governor.MIN_VOTING_DELAY() - 1));

        uint proposalId = uLarge.doPropose(targets, calldatas);

        hevm.roll(block.number + governor.votingDelay() + votingPeriod); // very last block
        uLarge.doCastVote(proposalId, true);

        hevm.roll(block.number + 1);
        uSmall.doQueue(proposalId);

        hevm.warp(now + pause.delay());
        uMedium.doExecute(proposalId);
    }

    function test_set_voting_period() public {
        uSmall.doDelegate(prot, address(uLarge));
        uMedium.doDelegate(prot, address(uLarge));
        uLarge3.doDelegate(prot, address(uLarge));
        uLarge2.doDelegate(prot, address(uLarge));

        hevm.roll(block.number + 1);

        targets.push(address(proxyActions));
        calldatas.push(abi.encodeWithSelector(proxyActions.setVotingPeriod.selector, address(governor), votingPeriod + 50));

        uint proposalId = uLarge.doPropose(targets, calldatas);

        hevm.roll(block.number + governor.votingDelay() + votingPeriod); // very last block
        uLarge.doCastVote(proposalId, true);

        hevm.roll(block.number + 1);
        uSmall.doQueue(proposalId);

        hevm.warp(now + pause.delay());
        uMedium.doExecute(proposalId);

        assertEq(governor.votingPeriod(), votingPeriod + 50);
    }

    function testFail_set_voting_period_unauthorized() public {
        governor._setVotingPeriod(votingPeriod + 1);
    }

    function testFail_set_voting_period_invalid() public {
        uSmall.doDelegate(prot, address(uLarge));
        uMedium.doDelegate(prot, address(uLarge));
        uLarge3.doDelegate(prot, address(uLarge));
        uLarge2.doDelegate(prot, address(uLarge));

        hevm.roll(block.number + 1);

        targets.push(address(proxyActions));
        calldatas.push(abi.encodeWithSelector(proxyActions.setVotingPeriod.selector, address(governor), governor.MAX_VOTING_PERIOD() + 1));

        uint proposalId = uLarge.doPropose(targets, calldatas);

        hevm.roll(block.number + governor.votingDelay() + votingPeriod); // very last block
        uLarge.doCastVote(proposalId, true);

        hevm.roll(block.number + 1);
        uSmall.doQueue(proposalId);

        hevm.warp(now + pause.delay());
        uMedium.doExecute(proposalId);
    }

    function testFail_set_voting_period_invalid2() public {
        uSmall.doDelegate(prot, address(uLarge));
        uMedium.doDelegate(prot, address(uLarge));
        uLarge3.doDelegate(prot, address(uLarge));
        uLarge2.doDelegate(prot, address(uLarge));

        hevm.roll(block.number + 1);

        targets.push(address(proxyActions));
        calldatas.push(abi.encodeWithSelector(proxyActions.setVotingPeriod.selector, address(governor), governor.MIN_VOTING_PERIOD() - 1));

        uint proposalId = uLarge.doPropose(targets, calldatas);

        hevm.roll(block.number + governor.votingDelay() + votingPeriod); // very last block
        uLarge.doCastVote(proposalId, true);

        hevm.roll(block.number + 1);
        uSmall.doQueue(proposalId);

        hevm.warp(now + pause.delay());
        uMedium.doExecute(proposalId);
    }


    function test_set_proposal_threshold() public {
        uSmall.doDelegate(prot, address(uLarge));
        uMedium.doDelegate(prot, address(uLarge));
        uLarge3.doDelegate(prot, address(uLarge));
        uLarge2.doDelegate(prot, address(uLarge));

        hevm.roll(block.number + 1);

        targets.push(address(proxyActions));
        calldatas.push(abi.encodeWithSelector(proxyActions.setProposalThreshold.selector, address(governor), proposalThreshold + 50));

        uint proposalId = uLarge.doPropose(targets, calldatas);

        hevm.roll(block.number + governor.votingDelay() + votingPeriod); // very last block
        uLarge.doCastVote(proposalId, true);

        hevm.roll(block.number + 1);
        uSmall.doQueue(proposalId);

        hevm.warp(now + pause.delay());
        uMedium.doExecute(proposalId);

        assertEq(governor.proposalThreshold(), proposalThreshold + 50);
    }

    function testFail_set_proposal_threshold_unauthorized() public {
        governor._setProposalThreshold(proposalThreshold + 1);
    }

    function testFail_set_proposal_threshold_invalid() public {
        uSmall.doDelegate(prot, address(uLarge));
        uMedium.doDelegate(prot, address(uLarge));
        uLarge3.doDelegate(prot, address(uLarge));
        uLarge2.doDelegate(prot, address(uLarge));

        hevm.roll(block.number + 1);

        targets.push(address(proxyActions));
        calldatas.push(abi.encodeWithSelector(proxyActions.setProposalThreshold.selector, address(governor), governor.MAX_PROPOSAL_THRESHOLD() + 1));

        uint proposalId = uLarge.doPropose(targets, calldatas);

        hevm.roll(block.number + governor.votingDelay() + votingPeriod); // very last block
        uLarge.doCastVote(proposalId, true);

        hevm.roll(block.number + 1);
        uSmall.doQueue(proposalId);

        hevm.warp(now + pause.delay());
        uMedium.doExecute(proposalId);
    }

    function testFail_set_proposal_threshold_invalid2() public {
        uSmall.doDelegate(prot, address(uLarge));
        uMedium.doDelegate(prot, address(uLarge));
        uLarge3.doDelegate(prot, address(uLarge));
        uLarge2.doDelegate(prot, address(uLarge));

        hevm.roll(block.number + 1);

        targets.push(address(proxyActions));
        calldatas.push(abi.encodeWithSelector(proxyActions.setProposalThreshold.selector, address(governor), governor.MIN_PROPOSAL_THRESHOLD() - 1));

        uint proposalId = uLarge.doPropose(targets, calldatas);

        hevm.roll(block.number + governor.votingDelay() + votingPeriod); // very last block
        uLarge.doCastVote(proposalId, true);

        hevm.roll(block.number + 1);
        uSmall.doQueue(proposalId);

        hevm.warp(now + pause.delay());
        uMedium.doExecute(proposalId);
    }

    function test_transfer_admin() public {
        uSmall.doDelegate(prot, address(uLarge));
        uMedium.doDelegate(prot, address(uLarge));
        uLarge3.doDelegate(prot, address(uLarge));
        uLarge2.doDelegate(prot, address(uLarge));

        hevm.roll(block.number + 1);

        targets.push(address(proxyActions));
        calldatas.push(abi.encodeWithSelector(proxyActions.setPendingAdmin.selector, address(governor), address(this)));

        uint proposalId = uLarge.doPropose(targets, calldatas);

        hevm.roll(block.number + governor.votingDelay() + votingPeriod); // very last block
        uLarge.doCastVote(proposalId, true);

        hevm.roll(block.number + 1);
        uSmall.doQueue(proposalId);

        hevm.warp(now + pause.delay());
        uMedium.doExecute(proposalId);

        governor._acceptAdmin();
        assertEq(governor.admin(), address(this));
    }

    function testFail_claim_ownership_unauthorized() public {
        governor._acceptAdmin();
    }

    function test_boosted_voting_power() public {
        assertEq(0, governor.getVotingPower(address(uSmall), block.number - 1));

        // unboosted voting power
        uSmall.doDelegate(prot, address(uSmall));
        hevm.roll(block.number + 1);

        assertEq(uSmallInitialBalance, governor.getVotingPower(address(uSmall), block.number - 1));

        // boosted voting power
        boost.mint(address(uSmall), uSmallInitialBalance);
        uSmall.doDelegate(boost, address(uSmall));
        hevm.roll(block.number + 1);

        assertEq(uSmallInitialBalance + (boostMultiplier * uSmallInitialBalance / WAD), governor.getVotingPower(address(uSmall), block.number - 1));
    }

    function test_boosted_voting_power_after_slash() public {
        assertEq(0, governor.getVotingPower(address(uMedium), block.number - 1));

        // unboosted voting power
        uMedium.doDelegate(prot, address(uMedium));
        hevm.roll(block.number + 1);

        assertEq(uMediumInitialBalance, governor.getVotingPower(address(uMedium), block.number - 1));

        uint boostBalance = 669 ether;

        // boosted voting power
        boost.mint(address(uMedium), boostBalance);
        uMedium.doDelegate(boost, address(uMedium));
        hevm.roll(block.number + 1);

        assertEq(uMediumInitialBalance + (boostMultiplier * boostBalance / WAD), governor.getVotingPower(address(uMedium), block.number - 1));

        // staking slashed
        staking.setDescendantPerAncestor(1.2 ether);
        assertEq(uMediumInitialBalance + (boostMultiplier * boostBalance / 1.2 ether), governor.getVotingPower(address(uMedium), block.number - 1));
    }

    function test_boosted_voting_power_fuzz(uint protBalance, uint boostBalance, uint slashingAmount) public {
        protBalance = protBalance % 1e9 ether; // up to 1 billion
        boostBalance = boostBalance % 1e9 ether; // up to 1 billion
        slashingAmount = 1 ether + (slashingAmount % 3 ether); // up to 75% slashing

        VoteQuorumUser voter = new VoteQuorumUser(governor);
        prot.mint(address(voter), protBalance);
        boost.mint(address(voter), boostBalance);
        voter.doDelegate(prot, address(voter));
        voter.doDelegate(boost, address(voter));
        hevm.roll(block.number + 1);
        staking.setDescendantPerAncestor(slashingAmount);

        assertEq(protBalance + (boostMultiplier * boostBalance / slashingAmount), governor.getVotingPower(address(voter), block.number - 1));
    }

    // takes too long for CI
    // function prove_boosted_voting_power(uint protBalance, uint boostBalance, uint slashingAmount) public {
    //     VoteQuorumUser voter = new VoteQuorumUser(governor);
    //     prot.mint(address(voter), protBalance);
    //     boost.mint(address(voter), boostBalance);
    //     voter.doDelegate(prot, address(voter));
    //     voter.doDelegate(boost, address(voter));
    //     hevm.roll(block.number + 1);
    //     staking.setDescendantPerAncestor(slashingAmount);

    //     assertEq(protBalance + (boostMultiplier * boostBalance / slashingAmount), governor.getVotingPower(address(voter), block.number - 1));
    // }
}
