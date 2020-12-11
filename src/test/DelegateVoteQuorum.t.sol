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

import "ds-test/test.sol";
import "ds-token/delegate.sol";
import "ds-thing/thing.sol";
import {DSDelegateRoles} from "ds-roles/delegate_roles.sol";
import "ds-pause/protest-pause.sol";

import "../DelegateVoteQuorum.sol";

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

contract GovActionsLike {
    function modifyParameter(DelegateVoteQuorum target, bytes32 parameter, uint value) public {
        target.modifyParameters(parameter, value);
    }

    function modifyParameters(DelegateVoteQuorum target, bytes32[] memory parameters, uint[] memory values) public {
        // require(parameters.length == values.length && values.length <= 5, "invalid-params");
        for (uint i = 0; i < values.length; i++)
            modifyParameter(target, parameters[i], values[i]);
    }
}

contract VoteQuorumUser is DSThing {
    DelegateVoteQuorum voteQuorum;

    constructor(DelegateVoteQuorum voteQuorum_) public {
        voteQuorum = voteQuorum_;
    }

    function doTransferFrom(DSToken token, address from, address to,
                            uint amount)
        public
        returns (bool)
    {
        return token.transferFrom(from, to, amount);
    }

    function doTransfer(DSToken token, address to, uint amount)
        public
        returns (bool)
    {
        return token.transfer(to, amount);
    }

    function doApprove(DSToken token, address recipient, uint amount)
        public
        returns (bool)
    {
        return token.approve(recipient, amount);
    }

    function doAllowance(DSToken token, address owner, address spender)
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

    function doPropose(DelegateVoteQuorum voteQuorum, DelegateVoteQuorum.ProposalType propoposalType, address proposalAddress, bytes32 proposalHash, bytes memory data, string memory description) public returns (uint) {
        return voteQuorum.propose(propoposalType, proposalAddress, proposalHash, data, description);
    }

    function doCancel(DelegateVoteQuorum voteQuorum, uint proposalId) public {
        return voteQuorum.cancel(proposalId);
    }

    function doCastVote(DelegateVoteQuorum voteQuorum, uint proposalId, bool support) public {
        return voteQuorum.castVote(proposalId, support);
    }

    function doExecute(DelegateVoteQuorum voteQuorum, uint proposalId) public {
        return voteQuorum.execute(proposalId);
    }

}

contract DelegateVoteQuorumTest is DSThing, DSTest {
    Hevm hevm;

    uint256 constant quorum = 10000 ether;
    uint256 constant proposalThreshold = 500 ether;
    uint256 constant votingPeriod = 100;
    uint256 constant proposalLifetime = 10000;

    // pause
    uint delay = 1 days;

    uint256 constant initialBalance = 10000000 ether;
    uint256 constant uLargeInitialBalance = initialBalance / 3000;
    uint256 constant uMediumInitialBalance = initialBalance / 4000;
    uint256 constant uSmallInitialBalance = initialBalance / 5000; 

    DelegateVoteQuorum voteQuorum;
    DSDelegateToken prot;
    DSProtestPause pause;
    Target govTarget;
    Target pauseTarget;
    GovActionsLike govActions;

    // u prefix: user
    VoteQuorumUser uWhale;
    VoteQuorumUser uLarge;
    VoteQuorumUser uLarge2;
    VoteQuorumUser uLarge3;
    VoteQuorumUser uMedium;
    VoteQuorumUser uSmall;

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.roll(10);

        govActions = new GovActionsLike();

        DSDelegateRoles roles = new DSDelegateRoles();
        pause = new DSProtestPause(4 hours, delay, msg.sender, roles);

        pauseTarget = new Target();
        pauseTarget.addAuthorization(address(pause.proxy()));
        pauseTarget.removeAuthorization(address(this));
        
        prot = new DSDelegateToken("PROT", "PROT");
        prot.mint(initialBalance);

        voteQuorum = new DelegateVoteQuorum(
            "delegateQuorum",
            quorum,
            proposalThreshold,
            votingPeriod,
            proposalLifetime,
            address(prot),
            address(pause)
        );

        govTarget = new Target();
        govTarget.addAuthorization(address(voteQuorum));
        govTarget.removeAuthorization(address(this));

        roles.setRootUser(address(voteQuorum), true);

        uWhale = new VoteQuorumUser(voteQuorum);
        uLarge = new VoteQuorumUser(voteQuorum);
        uLarge2 = new VoteQuorumUser(voteQuorum);
        uLarge3 = new VoteQuorumUser(voteQuorum);
        uMedium = new VoteQuorumUser(voteQuorum);
        uSmall = new VoteQuorumUser(voteQuorum);

        assert(initialBalance > uLargeInitialBalance + uMediumInitialBalance +
               uSmallInitialBalance);
        assert(uLargeInitialBalance < uMediumInitialBalance + uSmallInitialBalance);

        prot.transfer(address(uWhale), uLargeInitialBalance * 4);
        prot.transfer(address(uLarge), uLargeInitialBalance);
        prot.transfer(address(uLarge2), uLargeInitialBalance);
        prot.transfer(address(uLarge3), uLargeInitialBalance);
        prot.transfer(address(uMedium), uMediumInitialBalance);
        prot.transfer(address(uSmall), uSmallInitialBalance);

        hevm.roll(20);
    }

    function test_constructor() public {
        assert(voteQuorum.quorumVotes() == quorum);
        assert(voteQuorum.proposalThreshold() == proposalThreshold);
        assert(voteQuorum.votingPeriod() == votingPeriod);
        assert(voteQuorum.proposalLifetime() == proposalLifetime);
        assert(address(voteQuorum.protocolToken()) == address(prot));
        assert(address(voteQuorum.pause()) == address(pause));
    }

    function testFail_propose_not_enough_votes() public {
        uLarge.doPropose(voteQuorum, DelegateVoteQuorum.ProposalType.Arbitrary, address(govTarget), bytes32(0x0), bytes(""), "description");
    }

    function test_propose() public {
        uSmall.doDelegate(prot, address(uLarge));
        hevm.roll(block.number + 1);
        uint proposalId = uLarge.doPropose(voteQuorum, DelegateVoteQuorum.ProposalType.Arbitrary, address(govTarget), voteQuorum.extcodehash(address(govTarget)), bytes("0xabc"), "description");

        {
            (
                uint id, 
                DelegateVoteQuorum.ProposalType proposalType,
                address proposer, 
                address _target, 
                address usr, 
                bytes32 codeHash, 
                bytes memory data,,,,,,,
            ) = voteQuorum.proposals(proposalId);

            assertEq(id, proposalId);
            assertEq(uint(proposalType), uint(DelegateVoteQuorum.ProposalType.Arbitrary));
            assertEq(proposer, address(uLarge));
            assertEq(_target, address(pause));
            assertEq(usr, address(govTarget));
            assertEq(codeHash, voteQuorum.extcodehash(address(govTarget)));
            assertEq(keccak256(data), keccak256(bytes("0xabc")));
        }

        {
            (,,,,,,,
                uint startBlock, 
                uint voteEndBlock,
                uint lifetimeEndBlock,
                uint forVotes,
                uint againstVotes,
                bool canceled,
                bool scheduled
            ) = voteQuorum.proposals(proposalId);

            assertEq(startBlock, block.number + voteQuorum.votingDelay());
            assertEq(voteEndBlock, block.number + voteQuorum.votingDelay() + votingPeriod);
            assertEq(lifetimeEndBlock, startBlock + proposalLifetime);
        }
    }

    function testFail_already_pending_proposal() public {
        uSmall.doDelegate(prot, address(uLarge));
        
        hevm.roll(block.number + 1);
        uint proposalId = uLarge.doPropose(voteQuorum, DelegateVoteQuorum.ProposalType.Arbitrary, address(govTarget), bytes32("0x1"), bytes("0xabc"), "description");
        uLarge.doPropose(voteQuorum, DelegateVoteQuorum.ProposalType.Arbitrary, address(govTarget), bytes32("0x1"), bytes("0xabc"), "description");
    }

    function testFail_already_active_proposal() public {
        uSmall.doDelegate(prot, address(uLarge));
        
        hevm.roll(block.number + 1);
        uint proposalId = uLarge.doPropose(voteQuorum, DelegateVoteQuorum.ProposalType.Arbitrary, address(govTarget), bytes32("0x1"), bytes("0xabc"), "description");
        
        hevm.roll(block.number + 1 + votingPeriod);
        uLarge.doPropose(voteQuorum, DelegateVoteQuorum.ProposalType.Arbitrary, address(govTarget), bytes32("0x1"), bytes("0xabc"), "description");
    }

    function  test_execute_arbitrary_proposal() public {
        uSmall.doDelegate(prot, address(uLarge));
        uMedium.doDelegate(prot, address(uLarge3));
        uLarge3.doDelegate(prot, address(uLarge3));
        uLarge2.doDelegate(prot, address(uLarge3));
        
        hevm.roll(block.number + 1);
        bytes memory data = abi.encodeWithSelector(govTarget.set.selector, 20);
        uint proposalId = uLarge.doPropose(voteQuorum, DelegateVoteQuorum.ProposalType.Arbitrary, address(govTarget), voteQuorum.extcodehash(address(govTarget)), data, "description");
        
        hevm.roll(block.number + voteQuorum.votingDelay() + votingPeriod); // very last block
        uLarge.doCastVote(voteQuorum, proposalId, true);
        uLarge3.doCastVote(voteQuorum, proposalId, true);

        hevm.roll(block.number + 1);
        uMedium.doExecute(voteQuorum, proposalId);
        assertEq(govTarget.val(), 20);
    }

    function  test_execute_schedule_proposal() public {
        uSmall.doDelegate(prot, address(uLarge));
        uMedium.doDelegate(prot, address(uLarge));
        uLarge3.doDelegate(prot, address(uLarge));
        uLarge2.doDelegate(prot, address(uLarge));
        
        hevm.roll(block.number + 1);
        address usr = address(new SimpleAction());
        bytes memory data = abi.encodeWithSelector(SimpleAction.set.selector, pauseTarget, 30);
        uint proposalId = uLarge.doPropose(voteQuorum, DelegateVoteQuorum.ProposalType.Schedule, usr, voteQuorum.extcodehash(usr), data, "description");
        
        hevm.roll(block.number + voteQuorum.votingDelay() + votingPeriod); // very last block
        uLarge.doCastVote(voteQuorum, proposalId, true);

        hevm.roll(block.number + 1);
        uMedium.doExecute(voteQuorum, proposalId); // scheduled the proposal

        hevm.warp(now + pause.delay()); 
        pause.executeTransaction(usr, voteQuorum.extcodehash(usr), data, block.timestamp);

        assertEq(pauseTarget.val(), 30);
    }

    function  testFail_execute_abandoned_proposal() public {
        uSmall.doDelegate(prot, address(uLarge));
        uMedium.doDelegate(prot, address(uLarge));
        uLarge3.doDelegate(prot, address(uLarge));
        uLarge2.doDelegate(prot, address(uLarge));
        
        hevm.roll(block.number + 1);
        address usr = address(new SimpleAction());
        bytes memory data = abi.encodeWithSelector(SimpleAction.set.selector, pauseTarget, 30);
        uint proposalId = uLarge.doPropose(voteQuorum, DelegateVoteQuorum.ProposalType.Schedule, usr, voteQuorum.extcodehash(usr), data, "description");
        
        hevm.roll(block.number + voteQuorum.votingDelay() + votingPeriod); // very last block
        uLarge.doCastVote(voteQuorum, proposalId, true);

        hevm.roll(block.number + 1);
        uMedium.doExecute(voteQuorum, proposalId); // scheduled the proposal

        proposalId = uLarge.doPropose(voteQuorum, DelegateVoteQuorum.ProposalType.Abandon, usr, voteQuorum.extcodehash(usr), data, "description");

        hevm.roll(block.number + voteQuorum.votingDelay() + votingPeriod); // very last block
        uLarge.doCastVote(voteQuorum, proposalId, true);

        hevm.roll(block.number + 1);
        uMedium.doExecute(voteQuorum, proposalId); // abandoned the proposal

        hevm.warp(now + pause.delay()); 
        pause.executeTransaction(usr, voteQuorum.extcodehash(usr), data, block.timestamp);
    }

    function  testFail_execute_didnt_meet_quorum() public {
        uSmall.doDelegate(prot, address(uLarge));
        uLarge3.doDelegate(prot, address(uLarge3));
        uLarge2.doDelegate(prot, address(uLarge2));
        hevm.roll(block.number + 1);
        bytes memory data = abi.encodeWithSelector(govTarget.set.selector, 20);
        uint proposalId = uLarge.doPropose(voteQuorum, DelegateVoteQuorum.ProposalType.Arbitrary, address(govTarget), bytes32("0x1"), data, "description");
        hevm.roll(block.number + voteQuorum.votingDelay() + votingPeriod); // very last block
        uLarge.doCastVote(voteQuorum, proposalId, true);
        uLarge2.doCastVote(voteQuorum, proposalId, true);
        uLarge3.doCastVote(voteQuorum, proposalId, true);

        hevm.roll(block.number + 1);
        uMedium.doCastVote(voteQuorum, proposalId, true); // voting after finish
        uMedium.doExecute(voteQuorum, proposalId);
    }

    function  testFail_execute_more_con_votes() public {
        uWhale.doDelegate(prot, address(uWhale));
        uSmall.doDelegate(prot, address(uLarge));
        uMedium.doDelegate(prot, address(uMedium));
        uLarge3.doDelegate(prot, address(uLarge3));
        uLarge2.doDelegate(prot, address(uLarge2));
        
        hevm.roll(block.number + 1);
        bytes memory data = abi.encodeWithSelector(govTarget.set.selector, 20);
        uint proposalId = uLarge.doPropose(voteQuorum, DelegateVoteQuorum.ProposalType.Arbitrary, address(govTarget), bytes32("0x1"), data, "description");
        
        hevm.roll(block.number + voteQuorum.votingDelay() + votingPeriod); // very last block
        uMedium.doCastVote(voteQuorum, proposalId, true);
        uLarge.doCastVote(voteQuorum, proposalId, true);
        uLarge2.doCastVote(voteQuorum, proposalId, true);
        uLarge3.doCastVote(voteQuorum, proposalId, true);
        uWhale.doCastVote(voteQuorum, proposalId, false);

        hevm.roll(block.number + 1);
        uMedium.doExecute(voteQuorum, proposalId);
    }

    function  testFail_execute_twice() public {
        uSmall.doDelegate(prot, address(uLarge));
        uMedium.doDelegate(prot, address(uMedium));
        uLarge3.doDelegate(prot, address(uLarge3));
        uLarge2.doDelegate(prot, address(uLarge2));
        
        hevm.roll(block.number + 1);
        bytes memory data = abi.encodeWithSelector(govTarget.set.selector, 20);
        uint proposalId = uLarge.doPropose(voteQuorum, DelegateVoteQuorum.ProposalType.Arbitrary, address(govTarget), bytes32("0x1"), data, "description");
        
        hevm.roll(block.number + voteQuorum.votingDelay() + votingPeriod); // very last block
        uMedium.doCastVote(voteQuorum, proposalId, true);
        uLarge.doCastVote(voteQuorum, proposalId, true);
        uLarge2.doCastVote(voteQuorum, proposalId, true);
        uLarge3.doCastVote(voteQuorum, proposalId, true);

        hevm.roll(block.number + 1);
        uMedium.doExecute(voteQuorum, proposalId);
        uWhale.doExecute(voteQuorum, proposalId);
    }

    function  test_cancel() public {
        uSmall.doDelegate(prot, address(uLarge));
        uMedium.doDelegate(prot, address(uMedium));
        uLarge3.doDelegate(prot, address(uLarge3));
        uLarge2.doDelegate(prot, address(uLarge2));
        
        hevm.roll(block.number + 1);
        uint proposalId = uLarge.doPropose(voteQuorum, DelegateVoteQuorum.ProposalType.Arbitrary, address(govTarget), voteQuorum.extcodehash(address(govTarget)), bytes(""), "description");
        uSmall.doDelegate(prot, address(uSmall)); // bumping proposer below the threshold
        
        hevm.roll(block.number + voteQuorum.votingDelay() + votingPeriod); // very last block
        uMedium.doCastVote(voteQuorum, proposalId, true);
        uLarge.doCastVote(voteQuorum, proposalId, true);
        uLarge2.doCastVote(voteQuorum, proposalId, true);
        uLarge3.doCastVote(voteQuorum, proposalId, true);
        
        hevm.roll(block.number + 1);
        uLarge.doCancel(voteQuorum, proposalId); 

        (,,,,,,,,,,,, bool canceled,) = voteQuorum.proposals(proposalId);
        assertTrue(canceled);
    }

    function  testFail_cancel_above_threshold() public {
        uSmall.doDelegate(prot, address(uLarge));
        uMedium.doDelegate(prot, address(uMedium));
        uLarge3.doDelegate(prot, address(uLarge3));
        uLarge2.doDelegate(prot, address(uLarge2));
        
        hevm.roll(block.number + 1);
        uint proposalId = uLarge.doPropose(voteQuorum, DelegateVoteQuorum.ProposalType.Arbitrary, address(govTarget), bytes32("0x1"), bytes(""), "description");
        
        hevm.roll(block.number + voteQuorum.votingDelay() + votingPeriod); // very last block
        uMedium.doCastVote(voteQuorum, proposalId, true);
        uLarge.doCastVote(voteQuorum, proposalId, true);
        uLarge2.doCastVote(voteQuorum, proposalId, true);
        uLarge3.doCastVote(voteQuorum, proposalId, true);
        
        hevm.roll(block.number + 1); 
        uLarge.doCancel(voteQuorum, proposalId);
    }

    function  testFail_cancel_executed_proposal() public {
        uSmall.doDelegate(prot, address(uLarge));
        uMedium.doDelegate(prot, address(uMedium));
        uLarge3.doDelegate(prot, address(uLarge3));
        uLarge2.doDelegate(prot, address(uLarge2));

        hevm.roll(block.number + 1);
        bytes memory data = abi.encodeWithSelector(govTarget.set.selector, 20);
        uint proposalId = uLarge.doPropose(voteQuorum, DelegateVoteQuorum.ProposalType.Arbitrary, address(govTarget), bytes32("0x1"), data, "description");
        uSmall.doDelegate(prot, address(uSmall)); // bumping proposer below the threshold
        
        hevm.roll(block.number + voteQuorum.votingDelay() + votingPeriod); // very last block
        uMedium.doCastVote(voteQuorum, proposalId, true);
        uLarge.doCastVote(voteQuorum, proposalId, true);
        uLarge2.doCastVote(voteQuorum, proposalId, true);
        uLarge3.doCastVote(voteQuorum, proposalId, true);
        uSmall.doCastVote(voteQuorum, proposalId, true);

        hevm.roll(block.number + 1);
        uMedium.doExecute(voteQuorum, proposalId);
        assertEq(govTarget.val(), 20);

        uLarge.doCancel(voteQuorum, proposalId);
    }

    function _modifyParameter(bytes32 parameter, uint val) internal {
        uSmall.doDelegate(prot, address(uLarge));
        uMedium.doDelegate(prot, address(uLarge));
        uLarge3.doDelegate(prot, address(uLarge));
        uLarge2.doDelegate(prot, address(uLarge));
        
        hevm.roll(block.number + 1);
        address usr = address(govActions);
        bytes memory data = abi.encodeWithSelector(govActions.modifyParameter.selector, voteQuorum, parameter, val);
        uint proposalId = uLarge.doPropose(voteQuorum, DelegateVoteQuorum.ProposalType.Schedule, usr, voteQuorum.extcodehash(usr), data, "modifyParams");
        
        hevm.roll(block.number + voteQuorum.votingDelay() + voteQuorum.votingPeriod()); // very last block
        uLarge.doCastVote(voteQuorum, proposalId, true);

        hevm.roll(block.number + 1);
        uMedium.doExecute(voteQuorum, proposalId); // scheduled the proposal

        hevm.warp(now + pause.delay()); 
        pause.executeTransaction(usr, voteQuorum.extcodehash(usr), data, block.timestamp);
    }

    function  test_modify_parameters() public {
        _modifyParameter(bytes32("quorumVotes"), quorum + 1);
        assertEq(voteQuorum.quorumVotes(), quorum + 1);
        _modifyParameter(bytes32("proposalThreshold"), proposalThreshold + 1);
        assertEq(voteQuorum.proposalThreshold(), proposalThreshold + 1);
        _modifyParameter(bytes32("proposalLifetime"), proposalLifetime + 1);
        assertEq(voteQuorum.proposalLifetime(), proposalLifetime + 1);
        _modifyParameter(bytes32("votingDelay"), 2);
        assertEq(voteQuorum.votingDelay(), 2);
        _modifyParameter(bytes32("votingPeriod"), votingPeriod + 1);
        assertEq(voteQuorum.votingPeriod(), votingPeriod + 1);
    }

    function  testFail_modify_invalid_parameter() public {
        uSmall.doDelegate(prot, address(uLarge));
        uMedium.doDelegate(prot, address(uLarge));
        uLarge3.doDelegate(prot, address(uLarge));
        uLarge2.doDelegate(prot, address(uLarge));
        
        hevm.roll(block.number + 1);
        address usr = address(govActions);
        bytes memory data = abi.encodeWithSelector(govActions.modifyParameter.selector, voteQuorum, bytes32(""), 7000000 ether);
        uint proposalId = uLarge.doPropose(voteQuorum, DelegateVoteQuorum.ProposalType.Schedule, usr, voteQuorum.extcodehash(usr), data, "modifyParams");
        
        hevm.roll(block.number + voteQuorum.votingDelay() + votingPeriod); // very last block
        uLarge.doCastVote(voteQuorum, proposalId, true);

        hevm.roll(block.number + 1);
        uMedium.doExecute(voteQuorum, proposalId); // scheduled the proposal

        hevm.warp(now + pause.delay()); 
        pause.executeTransaction(usr, voteQuorum.extcodehash(usr), data, block.timestamp);

        assertEq(voteQuorum.quorumVotes(), 7000000 ether);
    }

}
