pragma solidity >=0.5.0;

import "ds-test/test.sol";
import "ds-token/token.sol";

import "./Chief.sol";

contract Voter {
    DSToken   gov;
    address chief;

    constructor(DSToken gov_, address chief_) public {
        gov   =   gov_;
        chief = chief_;
    }

    function approveChief() public { gov.approve(chief); }

    function tryLock(uint256 wad) public returns (bool ok) { 
        (ok, ) = chief.call(abi.encodeWithSignature(
            "lock(uint256)", wad
        ));
    }

    function tryFree(uint256 wad) public returns (bool ok) { 
        (ok, ) = chief.call(abi.encodeWithSignature(
            "free(uint256)", wad
        ));
    }

    function tryVote(bytes32 pick) public returns (bool ok) {
        (ok, ) = chief.call(abi.encodeWithSignature(
            "vote(bytes32)", pick
        ));
    }

    function tryExec(address app, bytes memory data) public returns (bool ok) { 
        (ok, ) = chief.call(abi.encodeWithSignature(
            "exec(address,bytes)", app, data
        ));
    }
}

contract Cache {
    uint256 public val;
    function set(uint256 val_) public { val = val_; }
}

contract CacheScript {
    function setCache(address target, uint256 val) public {
        Cache(target).set(val);
    }
}

contract ThresholdScript {
    uint256 public threshold; 
    function updateThreshold(uint val_) public { 
        threshold = val_; 
    }
}


contract ChiefTest is DSTest {
    Chief chief;
    DSToken gov;
    Cache cache;

    Voter ben;
    Voter sam;
    Voter ava;

    function setUp() public {
        gov = new DSToken("gov");
        chief = new Chief(address(gov));
        cache = new Cache();

        ben = new Voter(gov, address(chief));
        sam = new Voter(gov, address(chief));
        ava = new Voter(gov, address(chief));
        gov.mint(address(ben), 100 ether);
        gov.mint(address(sam), 100 ether);
        gov.mint(address(ava), 100 ether);
    }

    function test_sanity_setup_check() public {
        assertEq(chief.threshold(), 10 ** 18 / 2);
        assertEq(chief.locked(), 0);
        assertEq(address(chief.gov()), address(gov));
        assertEq(chief.balances(address(ben)), 0);
        assertEq(chief.picks(address(ben)), bytes32(0));

        assertEq(cache.val(), 0);

        assertEq(gov.balanceOf(address(ben)), 100 ether);
    }

    function test_lock_free() public {
        // ben gives chief unlimited approvals over his gov token
        ben.approveChief();

        // ben locks some gov in chief
        assertTrue(ben.tryLock(10 ether));
        assertEq(chief.balances(address(ben)), 10 ether);
        assertEq(chief.locked(), 10 ether);
        assertTrue(ben.tryLock(1 ether));
        assertEq(chief.balances(address(ben)), 11 ether);
        assertEq(chief.locked(), 11 ether);

        // ben frees the same amount of gov from chief
        assertTrue(ben.tryFree(11 ether));
        assertEq(chief.balances(address(ben)), 0);
        assertEq(chief.locked(), 0);
    }

    function test_vote_exec() public {
        ben.approveChief();
        assertTrue(ben.tryLock(10 ether));

        // create a useful contract for chief to delegatecall
        CacheScript cacheScript = new CacheScript();
        uint256 newVal = 123;

        // create a proposal 
        bytes memory data = abi.encodeWithSignature(
            "setCache(address,uint256)", cache, newVal
        );
        bytes32 proposal = keccak256(abi.encode(cacheScript, data));

        // ben votes for the proposal
        assertTrue(ben.tryVote(proposal));
        assertEq(chief.picks(address(ben)), proposal);
        assertEq(chief.votes(proposal), 10 ether);
        assertTrue(!chief.hasFired(proposal));

        // ben executes the proposal
        assertEq(cache.val(), 0);
        assertTrue(ben.tryExec(address(cacheScript), data));

        // the proposal was successfully executed
        assertEq(cache.val(), newVal);
        assertTrue(chief.hasFired(proposal));

        // the proposal can only be executed once
        assertTrue(!ben.tryExec(address(cacheScript), data));
    }

    function test_modify_threshold() public {
        ben.approveChief();
        assertTrue(ben.tryLock(10 ether));

        ThresholdScript thresholdScript = new ThresholdScript();
        uint256 newThreshold = 10 ** 18;

        uint256 oldThreshold = chief.threshold();
        assertTrue(newThreshold != oldThreshold);

        bytes memory data = abi.encodeWithSignature(
            "updateThreshold(uint256)", newThreshold
        );
        bytes32 proposal = keccak256(abi.encode(thresholdScript, data));

        assertTrue(ben.tryVote(proposal));
        assertTrue(ben.tryExec(address(thresholdScript), data));
        assertEq(chief.threshold(), newThreshold);
    }

    function test_fail_free_too_much() public {
        ben.approveChief();
        assertTrue( ben.tryLock(10 ether));
        assertTrue(!ben.tryFree(11 ether));

        sam.approveChief();
        assertTrue( sam.tryLock(10 ether));
        assertTrue( ben.tryFree(9 ether ));
        assertTrue( ben.tryFree(1 ether ));

        assertTrue(!ben.tryFree(1 ether ));
        assertTrue( sam.tryFree(10 ether));
    }
}
