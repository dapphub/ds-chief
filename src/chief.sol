pragma solidity ^0.4.15;

import 'ds-token/token.sol';
import 'ds-roles/roles.sol';
import 'ds-math/math.sol';

// The right way to use this contract is probably to mix it with some kind
// of `DSAuthority`, like with `ds-roles`.
//   SEE DSChief
contract DSChiefApprovals is DSMath {
    mapping(bytes32=>address[]) public slates;
    mapping(address=>bytes32) public votes;
    mapping(address=>uint128) public approvals;
    mapping(address=>uint128) public deposits;
    DSToken public GOV; // voting token that gets locked up
    DSToken public IOU; // non-voting representation of a token, for e.g. secondary voting mechanisms
    address public hat; // the chieftain's hat

    uint256 public MAX_YAYS;

    event LogLockFree(address indexed who, uint128 before, uint128 afterwards);
    event LogEtch(bytes32 indexed slate);
    event LogVote(address indexed who, bytes32 indexed slate, uint128 before, uint128 afterwards);
    event LogLift(address indexed hat_);

    // IOU constructed outside this contract reduces deployment costs significantly
    // lock/free/vote are quite sensitive to token invariants. Caution is advised.
    function DSChiefApprovals(DSToken GOV_, DSToken IOU_, uint MAX_YAYS_)
    {
        GOV = GOV_;
        IOU = IOU_;
        MAX_YAYS = MAX_YAYS_;
    }

    function lock(uint128 wad) {
        GOV.pull(msg.sender, wad);
        uint128 before = deposits[msg.sender];
        uint128 after_ = wadd(deposits[msg.sender], wad);
        IOU.mint(wad);
        IOU.push(msg.sender, wad);
        deposits[msg.sender] = after_;
        LogLockFree(msg.sender, before, after_);
    }
    function free(uint128 wad) {
        IOU.pull(msg.sender, wad);
        uint128 before = deposits[msg.sender];
        uint128 after_ = wsub(deposits[msg.sender], wad);
        IOU.burn(wad);
        GOV.push(msg.sender, wad);
        deposits[msg.sender] = after_;
        LogLockFree(msg.sender, before, after_);
    }

    function etch(address[] yays) returns (bytes32 slate) {
        require( yays.length < MAX_YAYS );
        bytes32 hash = sha3(yays);
        slates[hash] = yays;
        LogEtch(hash);
        return hash;
    }
    function addVote(bytes32 slate)
        internal
    {
        uint128 weight = deposits[msg.sender];
        var yays = slates[slate];
        for( uint i = 0; i < yays.length; i++ ) {
            approvals[yays[i]] += weight;
        }
    }
    function subVote(bytes32 slate)
        internal
    {
        uint128 weight = deposits[msg.sender];
        var yays = slates[slate];
        for( uint i = 0; i < yays.length; i++ ) {
            approvals[yays[i]] -= weight;
        }
    }
    function vote(bytes32 slate) {
        subVote(votes[msg.sender]);
        votes[msg.sender] = slate;
        addVote(votes[msg.sender]);
    }
    function vote(bytes32 slate, address lift_whom) {
        vote(slate);
        lift(lift_whom);
    }
    // like `drop`/`swap` except simply "elect this address if it is higher than current hat"
    function lift(address whom) {
        require(approvals[whom] > approvals[hat]);
        hat = whom;
        LogLift(whom);
    }
}


// `hat` address is unique root user (has every role) and the
// unique owner of role 0 (typically 'sys' or 'internal')
contract DSChief is DSRoles, DSChiefApprovals {

    function DSChief(DSToken GOV, DSToken IOU, uint MAX_YAYS)
             DSChiefApprovals (GOV, IOU, MAX_YAYS)
    {
    }

    function getUserRoles(address who)
        constant
        returns (bytes32)
    {
        if( who == hat ) {
            return BITNOT(0);
        } else {
            return super.getUserRoles(who);
        }
    }
    function isUserRoot(address who)
        constant
        returns (bool)
    {
        return (who == hat) || super.isUserRoot(who);
    }
    // function getCapabilityRoles
    // function isCapabilityPublic
    function setUserRole(address who, uint8 role, bool enabled) {
        require( role > 0 );
        super.setUserRole(who, role, enabled);
    }
    function setRootUser(address who, bool enabled) {
        require( who != hat || enabled == true ); // can't unset `hat`
        super.setRootUser(who, enabled);
    }

}


