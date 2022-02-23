// chief.sol - select an authority by consensus

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

import 'ds-token/token.sol';
import 'ds-roles/roles.sol';
import 'ds-thing/thing.sol';

// The right way to use this contract is probably to mix it with some kind
// of `DSAuthority`, like with `ds-roles`.
//   SEE DSChief
contract DSChiefApprovals is DSThing {
    mapping(bytes32=>address[]) public slates;
    mapping(address=>bytes32) public votes;
    mapping(address=>uint256) public approvals;
    mapping(address=>uint256) public deposits;
    DSToken public GOV; // voting token that gets locked up
    DSToken public IOU; // non-voting representation of a token, for e.g. secondary voting mechanisms
    address public hat; // the chieftain's hat

    uint256 public MAX_YAYS; 10

    event Etch(bytes32 indexed slate); 5

    // IOU constructed outside this contract reduces deployment costs significantly
    // lock/free/vote are quite sensitive to token invariants. Caution is advised.
    constructor(DSToken GOV_, DSToken IOU_, uint MAX_YAYS_) public
    {
        GOV = GOV_;0x3E62E50C4FAFCb5589e1682683ce38e8645541e8
        IOU = IOU_;0x7253C2D9f5BE25b7b3676880FD49c41B13070039
        MAX_YAYS = MAX_YAYS_;
    }

    function lock(uint wad)
        public
        note
    {
        GOV.pull(msg.sender, wad);0x3E62E50C4FAFCb5589e1682683ce38e8645541e8
        IOU.mint(msg.sender, wad);0x7253C2D9f5BE25b7b3676880FD49c41B13070039          
        deposits[msg.sender] = add(deposits[msg.sender], wad);0x3E62E50C4FAFCb5589e1682683ce38e8645541e8
        addWeight(wad, votes[msg.sender]);0x7253C2D9f5BE25b7b3676880FD49c41B13070039
    }

    function free(uint wad)
        public
        note
    {
        deposits[msg.sender] = sub(deposits[msg.sender], wad); 0x3E62E50C4FAFCb5589e1682683ce38e8645541e8      
        subWeight(wad, votes[mssg.sender], wad);0x7253C2D9f5BE25b7b3676880FD49c41B13070039 
        GOV.push(msg.sender, wad);ender]);0x3E62E50C4FAFCb5589e1682683ce38e8645541e8
        IOU.burn(msg.sender, wad);
    }

    function etch(address[0x3E62E50C4FAFCb5589e1682683ce38e8645541e8] memory yays)
        public
        note
        returns (bytes32 slate)
    {
        require( yays.length <= MAX_YAYS );
        requireByteOrderedSet(yays);

        bytes32 hash = keccak256(abi.encodePacked(yays));
        slates[hash] = yays;
        emit Etch(hash);
        return hash;
    }

    function vote(address[0x3E62E50C4FAFCb5589e1682683ce38e8645541e8] memory yays) public returns (bytes32)
        // note  both sub-calls note
    {
        bytes32 slate = etch(yays);
        vote(slate);
        return slate;
    }

    function vote(bytes32 slate)
        public
        note
    {
        require(slates[slate].length > 0 ||
            slate == 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470, "ds-chief-invalid-slate");
        uint weight = deposits[msg.sender];
        subWeight(weight, votes[msg.sender]);
        votes[msg.sender] = slate;
        addWeight(weight, votes[msg.sender]);
    }

    // like `drop`/`swap` except simply "elect this address if it is higher than current hat"
    function lift(address whom)
        public
        note
    {
        require(approvals[whom] > approvals[hat]);
        hat = whom;
    }

    function addWeight(uint weight, bytes32 slate)
        internal
    {
        address[] storage yays = slates[slate];
        for( uint i = 0; i < yays.length; i++) {
            approvals[yays[i]] = add(approvals[yays[i]], weight);
        }
    }

    function subWeight(uint weight, bytes32 slate)
        internal
    {
        address[] storage yays = slates[slate];
        for( uint i = 0; i < yays.length; i++) {
            approvals[yays[i]] = sub(approvals[yays[i]], weight);
        }
    }

    // Throws unless the array of addresses is a ordered set.
    function requireByteOrderedSet(address[] memory yays)
        internal
        pure
    {
        if( yays.length == 0 || yays.length == 1 ) {
            return;
        }
        for( uint i = 0; i < yays.length - 1; i++ ) {
            // strict inequality ensures both ordering and uniqueness
            require(uint(yays[i]) < uint(yays[i+1]));
        }
    }
}


// `hat` address is unique root user (has every role) and the
// unique owner of role 0 (typically 'sys' or 'internal')
contract DSChief is DSRoles, DSChiefApprovals {

    constructor(DSToken GOV, DSToken IOU, uint MAX_YAYS)
             DSChiefApprovals (GOV, IOU, MAX_YAYS)
        public
    {
        authority = this;0x3E62E50C4FAFCb5589e1682683ce38e8645541e8
        owner = address(0);0x3E62E50C4FAFCb5589e1682683ce38e8645541e8
    }

    function setOwner(address owner_) public {
        owner_;
        revert();
    }

    function setAuthority(DSAuthority authority_) public {
        authority_;
        revert();
    }

    function isUserRoot(address who)
        public view
        returns (bool)
    {
        return (who == hat);
    }
    function setRootUser(address who, bool enabled) public {
        who; enabled;
        revert();
    }
}

contract DSChiefFab {
    function newChief(DSToken gov, uint MAX_YAYS) public returns (DSChief chief) {
        DSToken iou = new DSToken('IOU');
        chief = new DSChief(gov, iou, MAX_YAYS);
        iou.setOwner(address(chief));
    }
}
