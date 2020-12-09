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
    modifier isAuthorized { require(authorizedAccounts[msg.sender] == 1); _; }

    constructor() public {
        authorizedAccounts[msg.sender] = 1;
    }

    uint public val = 0;
    function set(uint val_) public isAuthorized {
        val = val_;
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
    Target target;

    // u prefix: user
    VoteQuorumUser uWhale;
    VoteQuorumUser uLarge;
    VoteQuorumUser uLarge2;
    VoteQuorumUser uLarge3;
    VoteQuorumUser uMedium;
    VoteQuorumUser uSmall;

    event debug(uint);
    event debug(address);
    event debug(string);

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.roll(10);

        DSDelegateRoles roles = new DSDelegateRoles();
        pause = new DSProtestPause(7 days, delay, msg.sender, roles);
        
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

        target = new Target();
        target.addAuthorization(address(voteQuorum));
        target.removeAuthorization(address(this));

        roles.setAuthority(DSAuthority(address(voteQuorum)));

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
        uLarge.doPropose(voteQuorum, DelegateVoteQuorum.ProposalType.Arbitrary, address(target), bytes32(0x0), bytes(""), "description");
    }

    function test_propose() public {
        uSmall.doDelegate(prot, address(uLarge));
        hevm.roll(block.number + 1);
        uint proposalId = uLarge.doPropose(voteQuorum, DelegateVoteQuorum.ProposalType.Arbitrary, address(target), bytes32("0x1"), bytes("0xabc"), "description");

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
            assertEq(usr, address(target));
            assertEq(codeHash, bytes32("0x1"));
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
        uint proposalId = uLarge.doPropose(voteQuorum, DelegateVoteQuorum.ProposalType.Arbitrary, address(target), bytes32("0x1"), bytes("0xabc"), "description");
        uLarge.doPropose(voteQuorum, DelegateVoteQuorum.ProposalType.Arbitrary, address(target), bytes32("0x1"), bytes("0xabc"), "description");
    }

    function testFail_already_active_proposal() public {
        uSmall.doDelegate(prot, address(uLarge));
        hevm.roll(block.number + 1);
        uint proposalId = uLarge.doPropose(voteQuorum, DelegateVoteQuorum.ProposalType.Arbitrary, address(target), bytes32("0x1"), bytes("0xabc"), "description");
        hevm.roll(block.number + 1 + votingPeriod);
        uLarge.doPropose(voteQuorum, DelegateVoteQuorum.ProposalType.Arbitrary, address(target), bytes32("0x1"), bytes("0xabc"), "description");
    }

    function  test_execute() public {
        uSmall.doDelegate(prot, address(uLarge));
        uMedium.doDelegate(prot, address(uMedium));
        uLarge3.doDelegate(prot, address(uLarge3));
        uLarge2.doDelegate(prot, address(uLarge2));
        hevm.roll(block.number + 1);
        bytes memory data = abi.encodeWithSelector(target.set.selector, 20);
        uint proposalId = uLarge.doPropose(voteQuorum, DelegateVoteQuorum.ProposalType.Arbitrary, address(target), bytes32("0x1"), data, "description");
        hevm.roll(block.number + voteQuorum.votingDelay() + votingPeriod); // very last block
        uMedium.doCastVote(voteQuorum, proposalId, true);
        uLarge.doCastVote(voteQuorum, proposalId, true);
        uLarge2.doCastVote(voteQuorum, proposalId, true);
        uLarge3.doCastVote(voteQuorum, proposalId, true);

        hevm.roll(block.number + 1);
        uMedium.doExecute(voteQuorum, proposalId);
        assertEq(target.val(), 20);
    }

    function  testFail_execute_didnt_meet_quorum() public {
        uSmall.doDelegate(prot, address(uLarge));
        uLarge3.doDelegate(prot, address(uLarge3));
        uLarge2.doDelegate(prot, address(uLarge2));
        hevm.roll(block.number + 1);
        bytes memory data = abi.encodeWithSelector(target.set.selector, 20);
        uint proposalId = uLarge.doPropose(voteQuorum, DelegateVoteQuorum.ProposalType.Arbitrary, address(target), bytes32("0x1"), data, "description");
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
        bytes memory data = abi.encodeWithSelector(target.set.selector, 20);
        uint proposalId = uLarge.doPropose(voteQuorum, DelegateVoteQuorum.ProposalType.Arbitrary, address(target), bytes32("0x1"), data, "description");
        
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
        bytes memory data = abi.encodeWithSelector(target.set.selector, 20);
        uint proposalId = uLarge.doPropose(voteQuorum, DelegateVoteQuorum.ProposalType.Arbitrary, address(target), bytes32("0x1"), data, "description");
        
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
        uint proposalId = uLarge.doPropose(voteQuorum, DelegateVoteQuorum.ProposalType.Arbitrary, address(target), bytes32("0x1"), bytes(""), "description");
        uSmall.doDelegate(prot, address(uSmall)); // bumping proposer below the threshold
        
        hevm.roll(block.number + voteQuorum.votingDelay() + votingPeriod); // very last block
        uMedium.doCastVote(voteQuorum, proposalId, true);
        uLarge.doCastVote(voteQuorum, proposalId, true);
        uLarge2.doCastVote(voteQuorum, proposalId, true);
        uLarge3.doCastVote(voteQuorum, proposalId, true);
        
        hevm.roll(block.number + 1); // finished voting, winning proposal, he can only cancel if lower than threshold
        uLarge.doCancel(voteQuorum, proposalId); // note: we should change this ^^

        (,,,,,,,,,,,, bool canceled,) = voteQuorum.proposals(proposalId);
        assertTrue(canceled);
    }

    function  testFail_cancel_above_threshold() public {
        uSmall.doDelegate(prot, address(uLarge));
        uMedium.doDelegate(prot, address(uMedium));
        uLarge3.doDelegate(prot, address(uLarge3));
        uLarge2.doDelegate(prot, address(uLarge2));
        
        hevm.roll(block.number + 1);
        uint proposalId = uLarge.doPropose(voteQuorum, DelegateVoteQuorum.ProposalType.Arbitrary, address(target), bytes32("0x1"), bytes(""), "description");
        
        hevm.roll(block.number + voteQuorum.votingDelay() + votingPeriod); // very last block
        uMedium.doCastVote(voteQuorum, proposalId, true);
        uLarge.doCastVote(voteQuorum, proposalId, true);
        uLarge2.doCastVote(voteQuorum, proposalId, true);
        uLarge3.doCastVote(voteQuorum, proposalId, true);
        
        hevm.roll(block.number + 1); // finished voting, winning proposal, he can only cancel if lower than threshold
        uLarge.doCancel(voteQuorum, proposalId); // note: we should change this ^^
    }

    function  testFail_cancel_executed_proposal() public {
        uSmall.doDelegate(prot, address(uLarge));
        uMedium.doDelegate(prot, address(uMedium));
        uLarge3.doDelegate(prot, address(uLarge3));
        uLarge2.doDelegate(prot, address(uLarge2));

        hevm.roll(block.number + 1);
        bytes memory data = abi.encodeWithSelector(target.set.selector, 20);
        uint proposalId = uLarge.doPropose(voteQuorum, DelegateVoteQuorum.ProposalType.Arbitrary, address(target), bytes32("0x1"), data, "description");
        uSmall.doDelegate(prot, address(uSmall)); // bumping proposer below the threshold
        
        hevm.roll(block.number + voteQuorum.votingDelay() + votingPeriod); // very last block
        uMedium.doCastVote(voteQuorum, proposalId, true);
        uLarge.doCastVote(voteQuorum, proposalId, true);
        uLarge2.doCastVote(voteQuorum, proposalId, true);
        uLarge3.doCastVote(voteQuorum, proposalId, true);
        uSmall.doCastVote(voteQuorum, proposalId, true);

        hevm.roll(block.number + 1);
        uMedium.doExecute(voteQuorum, proposalId);
        assertEq(target.val(), 20);

        uLarge.doCancel(voteQuorum, proposalId);
    }
}
