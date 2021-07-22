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
import "ds-token/token.sol";
import {DSThing} from 'ds-thing/thing.sol';

import "../VoteQuorum.sol";

contract VoteQuorumUser is DSThing {
    VoteQuorum voteQuorum;

    constructor(VoteQuorum voteQuorum_) public {
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

    function doGroupCandidates(address[] memory guys) public returns (bytes32) {
        return voteQuorum.groupCandidates(guys);
    }

    function doVote(address[] memory guys) public returns (bytes32) {
        return voteQuorum.vote(guys);
    }

    function doVote(address[] memory guys, address elect_whom) public returns (bytes32) {
        bytes32 ballot = voteQuorum.vote(guys);
        voteQuorum.electCandidate(elect_whom);
        return ballot;
    }

    function doVote(bytes32 id) public {
        voteQuorum.vote(id);
    }

    function doVote(bytes32 id, address elect_whom) public {
        voteQuorum.vote(id);
        voteQuorum.electCandidate(elect_whom);
    }

    function doLift(address to_elect) public {
        voteQuorum.electCandidate(to_elect);
    }

    function doAddVotingWeight(uint amt) public {
        voteQuorum.addVotingWeight(amt);
    }

    function doRemoveVotingWeight(uint amt) public {
        voteQuorum.removeVotingWeight(amt);
    }

    function doSetUserRole(address who, uint8 role, bool enabled) public {
        voteQuorum.setUserRole(who, role, enabled);
    }

    function doSetRoleCapability(uint8 role, address code, bytes4 sig, bool enabled) public {
        voteQuorum.setRoleCapability(role, code, sig, enabled);
    }

    function doSetPublicCapability(address code, bytes4 sig, bool enabled) public {
        voteQuorum.setPublicCapability(code, sig, enabled);
    }

    function authedFn() public view auth returns (bool) {
        return true;
    }
}

contract VoteQuorumTest is DSThing, DSTest {
    uint256 constant electionSize = 3;

    // c prefix: candidate
    address constant c1 = address(0x1);
    address constant c2 = address(0x2);
    address constant c3 = address(0x3);
    address constant c4 = address(0x4);
    address constant c5 = address(0x5);
    address constant c6 = address(0x6);
    address constant c7 = address(0x7);
    address constant c8 = address(0x8);
    address constant c9 = address(0x9);
    uint256 constant initialBalance = 1000 ether;
    uint256 constant uLargeInitialBalance = initialBalance / 3;
    uint256 constant uMediumInitialBalance = initialBalance / 4;
    uint256 constant uSmallInitialBalance = initialBalance / 5;

    VoteQuorum voteQuorum;
    DSToken prot;
    DSToken iou;

    // u prefix: user
    VoteQuorumUser uLarge;
    VoteQuorumUser uMedium;
    VoteQuorumUser uSmall;

    function setUp() public {
        prot = new DSToken("PROT", "PROT");
        prot.mint(initialBalance);

        VoteQuorumFactory fab = new VoteQuorumFactory();
        voteQuorum = fab.newVoteQuorum(prot, electionSize);
        iou = voteQuorum.IOU();

        uLarge = new VoteQuorumUser(voteQuorum);
        uMedium = new VoteQuorumUser(voteQuorum);
        uSmall = new VoteQuorumUser(voteQuorum);

        assert(initialBalance > uLargeInitialBalance + uMediumInitialBalance +
               uSmallInitialBalance);
        assert(uLargeInitialBalance < uMediumInitialBalance + uSmallInitialBalance);

        prot.transfer(address(uLarge), uLargeInitialBalance);
        prot.transfer(address(uMedium), uMediumInitialBalance);
        prot.transfer(address(uSmall), uSmallInitialBalance);
    }

    function test_basic_sanity() public pure {
        assert(true);
    }

    function testFail_basic_sanity() public pure {
        assert(false);
    }

    function test_group_candidates_returns_same_id_for_same_sets() public {
        address[] memory candidates = new address[](3);
        candidates[0] = c1;
        candidates[1] = c2;
        candidates[2] = c3;

        bytes32 id = uSmall.doGroupCandidates(candidates);
        assert(id != 0x0);
        assertEq32(id, uMedium.doGroupCandidates(candidates));
    }

    function test_size_zero_ballot() public {
        address[] memory candidates = new address[](0);
        bytes32 id = uSmall.doGroupCandidates(candidates);
        uSmall.doVote(id);
    }
    function test_size_one_ballot() public {
        address[] memory candidates = new address[](1);
        candidates[0] = c1;
        bytes32 id = uSmall.doGroupCandidates(candidates);
        uSmall.doVote(id);
    }

    function testFail_group_candidates_requires_ordered_sets() public {
        address[] memory candidates = new address[](3);
        candidates[0] = c2;
        candidates[1] = c1;
        candidates[2] = c3;

        uSmall.doGroupCandidates(candidates);
    }

    function test_add_weight_debits_user() public {
        assert(prot.balanceOf(address(uLarge)) == uLargeInitialBalance);

        uint lockedAmt = uLargeInitialBalance / 10;
        uLarge.doApprove(prot, address(voteQuorum), lockedAmt);
        uLarge.doAddVotingWeight(lockedAmt);

        assert(prot.balanceOf(address(uLarge)) == uLargeInitialBalance - lockedAmt);
    }

    function test_changing_weight_after_voting() public {
        uint uLargeLockedAmt = uLargeInitialBalance / 2;
        uLarge.doApprove(iou, address(voteQuorum), uLargeLockedAmt);
        uLarge.doApprove(prot, address(voteQuorum), uLargeLockedAmt);
        uLarge.doAddVotingWeight(uLargeLockedAmt);

        address[] memory uLargeSlate = new address[](1);
        uLargeSlate[0] = c1;
        uLarge.doVote(uLargeSlate);

        assert(voteQuorum.approvals(c1) == uLargeLockedAmt);

        // Changing weight should update the weight of our candidate.
        uLarge.doRemoveVotingWeight(uLargeLockedAmt);
        assert(voteQuorum.approvals(c1) == 0);

        uLargeLockedAmt = uLargeInitialBalance / 4;
        uLarge.doApprove(prot, address(voteQuorum), uLargeLockedAmt);
        uLarge.doAddVotingWeight(uLargeLockedAmt);

        assert(voteQuorum.approvals(c1) == uLargeLockedAmt);
    }

    function test_voting_and_reordering() public {
        assert(prot.balanceOf(address(uLarge)) == uLargeInitialBalance);

        initial_vote();

        // Upset the order.
        uint uLargeLockedAmt = uLargeInitialBalance;
        uLarge.doApprove(prot, address(voteQuorum), uLargeLockedAmt);
        uLarge.doAddVotingWeight(uLargeLockedAmt);

        address[] memory uLargeSlate = new address[](1);
        uLargeSlate[0] = c3;
        uLarge.doVote(uLargeSlate);
    }

    function testFail_elect_while_out_of_order() public {
        initial_vote();

        // Upset the order.
        uSmall.doApprove(prot, address(voteQuorum), uSmallInitialBalance);
        uSmall.doAddVotingWeight(uSmallInitialBalance);

        address[] memory uSmallSlate = new address[](1);
        uSmallSlate[0] = c3;
        uSmall.doVote(uSmallSlate);

        uMedium.doRemoveVotingWeight(uMediumInitialBalance);

        voteQuorum.electCandidate(c3);
    }

    function test_elect_half_approvals() public {
        initial_vote();

        // Upset the order.
        uSmall.doApprove(prot, address(voteQuorum), uSmallInitialBalance);
        uSmall.doAddVotingWeight(uSmallInitialBalance);

        address[] memory uSmallSlate = new address[](1);
        uSmallSlate[0] = c3;
        uSmall.doVote(uSmallSlate);

        uMedium.doApprove(iou, address(voteQuorum), uMediumInitialBalance);
        uMedium.doRemoveVotingWeight(uMediumInitialBalance);

        voteQuorum.electCandidate(c3);

        assert(!voteQuorum.isUserRoot(c1));
        assert(!voteQuorum.isUserRoot(c2));
        assert(voteQuorum.isUserRoot(c3));
    }

    function testFail_voting_and_reordering_without_weight() public {
        assert(prot.balanceOf(address(uLarge)) == uLargeInitialBalance);

        initial_vote();

        // Vote without weight.
        address[] memory uLargeSlate = new address[](1);
        uLargeSlate[0] = c3;
        uLarge.doVote(uLargeSlate);

        // Attempt to update the elected set.
        voteQuorum.electCandidate(c3);
    }

    function test_voting_by_ballot_id() public {
        assert(prot.balanceOf(address(uLarge)) == uLargeInitialBalance);

        bytes32 ballotID = initial_vote();

        // Upset the order.
        uLarge.doApprove(prot, address(voteQuorum), uLargeInitialBalance);
        uLarge.doAddVotingWeight(uLargeInitialBalance);

        address[] memory uLargeSlate = new address[](1);
        uLargeSlate[0] = c4;
        uLarge.doVote(uLargeSlate);

        // Update the elected set to reflect the new order.
        voteQuorum.electCandidate(c4);

        // Now restore the old order using a ballot ID.
        uSmall.doApprove(prot, address(voteQuorum), uSmallInitialBalance);
        uSmall.doAddVotingWeight(uSmallInitialBalance);
        uSmall.doVote(ballotID);

        // Update the elected set to reflect the restored order.
        voteQuorum.electCandidate(c1);
    }

    function testFail_non_voted_authority_can_not_set_roles() public {
        uSmall.doSetUserRole(address(uMedium), 1, true);
    }

    function test_voted_authority_can_set_roles() public {
        address[] memory ballot = new address[](1);
        ballot[0] = address(uSmall);

        // Upset the order.
        uLarge.doApprove(prot, address(voteQuorum), uLargeInitialBalance);
        uLarge.doAddVotingWeight(uLargeInitialBalance);

        uLarge.doVote(ballot);

        // Update the elected set to reflect the new order.
        voteQuorum.electCandidate(address(uSmall));

        uSmall.doSetUserRole(address(uMedium), 1, true);
    }

    function testFail_non_voted_authority_can_not_role_capability() public {
        uSmall.doSetRoleCapability(1, address(uMedium), S("authedFn"), true);
    }

    function test_voted_authority_can_set_role_capability() public {
        address[] memory ballot = new address[](1);
        ballot[0] = address(uSmall);

        // Upset the order.
        uLarge.doApprove(prot, address(voteQuorum), uLargeInitialBalance);
        uLarge.doAddVotingWeight(uLargeInitialBalance);

        uLarge.doVote(ballot);

        // Update the elected set to reflect the new order.
        voteQuorum.electCandidate(address(uSmall));

        uSmall.doSetRoleCapability(1, address(uLarge), S("authedFn()"), true);
        uSmall.doSetUserRole(address(this), 1, true);

        uLarge.setAuthority(voteQuorum);
        uLarge.setOwner(address(0));
        uLarge.authedFn();
    }

    function test_voted_authority_can_set_public_capability() public {
        address[] memory ballot = new address[](1);
        ballot[0] = address(uSmall);

        // Upset the order.
        uLarge.doApprove(prot, address(voteQuorum), uLargeInitialBalance);
        uLarge.doAddVotingWeight(uLargeInitialBalance);

        uLarge.doVote(ballot);

        // Update the elected set to reflect the new order.
        voteQuorum.electCandidate(address(uSmall));

        uSmall.doSetPublicCapability(address(uLarge), S("authedFn()"), true);

        uLarge.setAuthority(voteQuorum);
        uLarge.setOwner(address(0));
        uLarge.authedFn();
    }

    function test_vote_quorum_no_owner() public {
        assertEq(voteQuorum.owner(), address(0));
    }

    function initial_vote() internal returns (bytes32 ballotID) {
        uint uMediumLockedAmt = uMediumInitialBalance;
        uMedium.doApprove(prot, address(voteQuorum), uMediumLockedAmt);
        uMedium.doAddVotingWeight(uMediumLockedAmt);

        address[] memory uMediumSlate = new address[](3);
        uMediumSlate[0] = c1;
        uMediumSlate[1] = c2;
        uMediumSlate[2] = c3;
        ballotID = uMedium.doVote(uMediumSlate);

        // Elect the most voted candidate.
        voteQuorum.electCandidate(c1);
    }
}
