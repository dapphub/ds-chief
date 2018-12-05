// chief.t.sol - test for chief.sol

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

pragma solidity >=0.4.23;

import "ds-test/test.sol";
import "ds-token/token.sol";
import "ds-thing/thing.sol";

import "./chief.sol";

contract ChiefUser is DSThing {
    DSChief chief;

    constructor(DSChief chief_) public {
        chief = chief_;
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

    function doEtch(address[] memory guys) public returns (bytes32) {
        return chief.etch(guys);
    }

    function doVote(address[] memory guys) public returns (bytes32) {
        return chief.vote(guys);
    }

    function doVote(address[] memory guys, address lift_whom) public returns (bytes32) {
        bytes32 slate = chief.vote(guys);
        chief.lift(lift_whom);
        return slate;
    }

    function doVote(bytes32 id) public {
        chief.vote(id);
    }

    function doVote(bytes32 id, address lift_whom) public {
        chief.vote(id);
        chief.lift(lift_whom);
    }

    function doLift(address to_lift) public {
        chief.lift(to_lift);
    }

    function doLock(uint amt) public {
        chief.lock(amt);
    }

    function doFree(uint amt) public {
        chief.free(amt);
    }

    function doSetUserRole(address who, uint8 role, bool enabled) public {
        chief.setUserRole(who, role, enabled);
    }

    function doSetRoleCapability(uint8 role, address code, bytes4 sig, bool enabled) public {
        chief.setRoleCapability(role, code, sig, enabled);
    }

    function doSetPublicCapability(address code, bytes4 sig, bool enabled) public {
        chief.setPublicCapability(code, sig, enabled);
    }

    function authedFn() public view auth returns (bool) {
        return true;
    }
}

contract DSChiefTest is DSThing, DSTest {
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

    DSChief chief;
    DSToken gov;
    DSToken iou;

    // u prefix: user
    ChiefUser uLarge;
    ChiefUser uMedium;
    ChiefUser uSmall;

    function setUp() public {
        gov = new DSToken("GOV");
        gov.mint(initialBalance);

        DSChiefFab fab = new DSChiefFab();
        chief = fab.newChief(gov, electionSize);
        iou = chief.IOU();

        uLarge = new ChiefUser(chief);
        uMedium = new ChiefUser(chief);
        uSmall = new ChiefUser(chief);

        assert(initialBalance > uLargeInitialBalance + uMediumInitialBalance +
               uSmallInitialBalance);
        assert(uLargeInitialBalance < uMediumInitialBalance + uSmallInitialBalance);

        gov.transfer(address(uLarge), uLargeInitialBalance);
        gov.transfer(address(uMedium), uMediumInitialBalance);
        gov.transfer(address(uSmall), uSmallInitialBalance);
    }

    function test_basic_sanity() public pure {
        assert(true);
    }

    function testFail_basic_sanity() public pure {
        assert(false);
    }

    function test_etch_returns_same_id_for_same_sets() public {
        address[] memory candidates = new address[](3);
        candidates[0] = c1;
        candidates[1] = c2;
        candidates[2] = c3;

        bytes32 id = uSmall.doEtch(candidates);
        assert(id != 0x0);
        assertEq32(id, uMedium.doEtch(candidates));
    }

    function test_size_zero_slate() public {
        address[] memory candidates = new address[](0);
        bytes32 id = uSmall.doEtch(candidates);
        uSmall.doVote(id);
    }
    function test_size_one_slate() public {
        address[] memory candidates = new address[](1);
        candidates[0] = c1;
        bytes32 id = uSmall.doEtch(candidates);
        uSmall.doVote(id);
    }

    function testFail_etch_requires_ordered_sets() public {
        address[] memory candidates = new address[](3);
        candidates[0] = c2;
        candidates[1] = c1;
        candidates[2] = c3;

        uSmall.doEtch(candidates);
    }

    function test_lock_debits_user() public {
        assert(gov.balanceOf(address(uLarge)) == uLargeInitialBalance);

        uint lockedAmt = uLargeInitialBalance / 10;
        uLarge.doApprove(gov, address(chief), lockedAmt);
        uLarge.doLock(lockedAmt);

        assert(gov.balanceOf(address(uLarge)) == uLargeInitialBalance - lockedAmt);
    }

    function test_changing_weight_after_voting() public {
        uint uLargeLockedAmt = uLargeInitialBalance / 2;
        uLarge.doApprove(iou, address(chief), uLargeLockedAmt);
        uLarge.doApprove(gov, address(chief), uLargeLockedAmt);
        uLarge.doLock(uLargeLockedAmt);

        address[] memory uLargeSlate = new address[](1);
        uLargeSlate[0] = c1;
        uLarge.doVote(uLargeSlate);

        assert(chief.approvals(c1) == uLargeLockedAmt);

        // Changing weight should update the weight of our candidate.
        uLarge.doFree(uLargeLockedAmt);
        assert(chief.approvals(c1) == 0);

        uLargeLockedAmt = uLargeInitialBalance / 4;
        uLarge.doApprove(gov, address(chief), uLargeLockedAmt);
        uLarge.doLock(uLargeLockedAmt);

        assert(chief.approvals(c1) == uLargeLockedAmt);
    }

    function test_voting_and_reordering() public {
        assert(gov.balanceOf(address(uLarge)) == uLargeInitialBalance);

        initial_vote();

        // Upset the order.
        uint uLargeLockedAmt = uLargeInitialBalance;
        uLarge.doApprove(gov, address(chief), uLargeLockedAmt);
        uLarge.doLock(uLargeLockedAmt);

        address[] memory uLargeSlate = new address[](1);
        uLargeSlate[0] = c3;
        uLarge.doVote(uLargeSlate);
    }

    function testFail_lift_while_out_of_order() public {
        initial_vote();

        // Upset the order.
        uSmall.doApprove(gov, address(chief), uSmallInitialBalance);
        uSmall.doLock(uSmallInitialBalance);

        address[] memory uSmallSlate = new address[](1);
        uSmallSlate[0] = c3;
        uSmall.doVote(uSmallSlate);

        uMedium.doFree(uMediumInitialBalance);

        chief.lift(c3);
    }

    function test_lift_half_approvals() public {
        initial_vote();

        // Upset the order.
        uSmall.doApprove(gov, address(chief), uSmallInitialBalance);
        uSmall.doLock(uSmallInitialBalance);

        address[] memory uSmallSlate = new address[](1);
        uSmallSlate[0] = c3;
        uSmall.doVote(uSmallSlate);

        uMedium.doApprove(iou, address(chief), uMediumInitialBalance);
        uMedium.doFree(uMediumInitialBalance);

        chief.lift(c3);

        assert(!chief.isUserRoot(c1));
        assert(!chief.isUserRoot(c2));
        assert(chief.isUserRoot(c3));
    }

    function testFail_voting_and_reordering_without_weight() public {
        assert(gov.balanceOf(address(uLarge)) == uLargeInitialBalance);

        initial_vote();

        // Vote without weight.
        address[] memory uLargeSlate = new address[](1);
        uLargeSlate[0] = c3;
        uLarge.doVote(uLargeSlate);

        // Attempt to update the elected set.
        chief.lift(c3);
    }

    function test_voting_by_slate_id() public {
        assert(gov.balanceOf(address(uLarge)) == uLargeInitialBalance);

        bytes32 slateID = initial_vote();

        // Upset the order.
        uLarge.doApprove(gov, address(chief), uLargeInitialBalance);
        uLarge.doLock(uLargeInitialBalance);

        address[] memory uLargeSlate = new address[](1);
        uLargeSlate[0] = c4;
        uLarge.doVote(uLargeSlate);

        // Update the elected set to reflect the new order.
        chief.lift(c4);

        // Now restore the old order using a slate ID.
        uSmall.doApprove(gov, address(chief), uSmallInitialBalance);
        uSmall.doLock(uSmallInitialBalance);
        uSmall.doVote(slateID);

        // Update the elected set to reflect the restored order.
        chief.lift(c1);
    }

    function testFail_non_hat_can_not_set_roles() public {
        uSmall.doSetUserRole(address(uMedium), 1, true);
    }

    function test_hat_can_set_roles() public {
        address[] memory slate = new address[](1);
        slate[0] = address(uSmall);

        // Upset the order.
        uLarge.doApprove(gov, address(chief), uLargeInitialBalance);
        uLarge.doLock(uLargeInitialBalance);

        uLarge.doVote(slate);

        // Update the elected set to reflect the new order.
        chief.lift(address(uSmall));

        uSmall.doSetUserRole(address(uMedium), 1, true);
    }

    function testFail_non_hat_can_not_role_capability() public {
        uSmall.doSetRoleCapability(1, address(uMedium), S("authedFn"), true);
    }

    function test_hat_can_set_role_capability() public {
        address[] memory slate = new address[](1);
        slate[0] = address(uSmall);

        // Upset the order.
        uLarge.doApprove(gov, address(chief), uLargeInitialBalance);
        uLarge.doLock(uLargeInitialBalance);

        uLarge.doVote(slate);

        // Update the elected set to reflect the new order.
        chief.lift(address(uSmall));

        uSmall.doSetRoleCapability(1, address(uLarge), S("authedFn()"), true);
        uSmall.doSetUserRole(address(this), 1, true);

        uLarge.setAuthority(chief);
        uLarge.setOwner(address(0));
        uLarge.authedFn();
    }

    function test_hat_can_set_public_capability() public {
        address[] memory slate = new address[](1);
        slate[0] = address(uSmall);

        // Upset the order.
        uLarge.doApprove(gov, address(chief), uLargeInitialBalance);
        uLarge.doLock(uLargeInitialBalance);

        uLarge.doVote(slate);

        // Update the elected set to reflect the new order.
        chief.lift(address(uSmall));

        uSmall.doSetPublicCapability(address(uLarge), S("authedFn()"), true);

        uLarge.setAuthority(chief);
        uLarge.setOwner(address(0));
        uLarge.authedFn();
    }

    function test_chief_no_owner() public {
        assertEq(chief.owner(), address(0));
    }

    function initial_vote() internal returns (bytes32 slateID) {
        uint uMediumLockedAmt = uMediumInitialBalance;
        uMedium.doApprove(gov, address(chief), uMediumLockedAmt);
        uMedium.doLock(uMediumLockedAmt);

        address[] memory uMediumSlate = new address[](3);
        uMediumSlate[0] = c1;
        uMediumSlate[1] = c2;
        uMediumSlate[2] = c3;
        slateID = uMedium.doVote(uMediumSlate);

        // Lift the chief.
        chief.lift(c1);
    }
}
