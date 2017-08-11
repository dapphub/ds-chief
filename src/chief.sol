import 'ds-token/token.sol';
import 'ds-roles/roles.sol';

// The right way to use this contract is probably to mix it with some kind
// of `DSAuthority`, like with `ds-roles`.
contract DSChiefApprovals {
    mapping(bytes32=>address[]) slates;
    mapping(address=>bytes32) votes;
    mapping(address=>uint256) approvals;
    mapping(address=>uint256) deposits;
    DSToken public GOV; // voting token that gets locked up
    DSToken public IOU; // non-voting representation of a token, for e.g. secondary voting mechanisms
    address public hat; // the chieftain's hat

    uint256 public MAX_YAYS;

    // IOU constructed outside this contract reduces deployment costs significantly
    // lock/free/vote are quite sensitive to token invariants. Caution is advised.
    function Approval(uint MAX_YAYS_, DSToken GOV_, DSToken IOU_) {
        GOV = GOV_;
        IOU = IOU_;
        MAX_YAYS = MAX_YAYS_;
    }

    function lock(uint128 wad) {
        GOV.pull(msg.sender, wad);
        deposits[msg.sender] += wad;
        IOU.mint(wad);
        IOU.push(msg.sender, wad);
    }
    function free(uint128 wad) {
        IOU.pull(msg.sender, wad);
        IOU.burn(wad);
        deposits[msg.sender] -= wad;
        GOV.push(msg.sender, wad);
    }

    function etch(address[] yays) returns (bytes32 slate) {
        require( yays.length < MAX_YAYS );
        bytes32 hash = sha3(yays);
        slates[hash] = yays;
        return hash;
    }
    function addVote(bytes32 slate)
        internal
    {
        uint weight = deposits[msg.sender];
        var yays = slates[slate];
        for( uint i = 0; i < yays.length; i++ ) {
            approvals[yays[i]] += weight;
        }
    }
    function subVote(bytes32 slate)
        internal
    {
        uint weight = deposits[msg.sender];
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
    }
}


// `hat` address is unique root user (has every role) and the
// unique owner of role 0 (typically 'sys' or 'internal')
contract DSChief is DSRoles {
    // override
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
        if( who == hat ) {
            return true;
        } else  {
            return super.isUserRoot(who);
        }
    }
    // function getCapabilityRoles
    // function isCapabilityPublic
    function setUserRole(address who, uint8 role, bool enabled) {
        if( role == 0 ) {
            throw;
        } else {
            super.setUserRole(who, role, enabled);
        }
    }
    function setRootUser(address who, bool enabled) {
        throw;
    }

}


