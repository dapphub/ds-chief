// VoteQuorum.sol - select an authority by consensus

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

import 'ds-token/token.sol';
import 'ds-roles/roles.sol';
import {DSThing} from 'ds-thing/thing.sol';

// The right way to use this contract is probably to mix it with some kind
// of `DSAuthority`, like with `ds-roles`.
//   SEE VoteQuorum
contract VoteQuorumApprovals is DSThing {
    mapping(bytes32=>address[]) public ballots;
    mapping(address=>bytes32) public votes;
    mapping(address=>uint256) public approvals;
    mapping(address=>uint256) public deposits;
    DSToken public PROT; // protocol token that gets locked up
    DSToken public IOU;  // non-voting representation of a token, for e.g. secondary voting mechanisms
    address public votedAuthority; // the quorum's chosen authority

    uint256 public MAX_CANDIDATES_PER_BALLOT;

    event AddVotingWeight(address voter, uint wad);
    event RemoveVotingWeight(address voter, uint wad);
    event GroupCandidates(address[] candidates, bytes32 indexed ballot);
    event Vote(address voter, address[] candidates, bytes32 indexed ballot);
    event Vote(address voter, bytes32 indexed ballot);
    event ElectCandidate(address sender, address whom);

    // IOU constructed outside this contract reduces deployment costs significantly
    // addVotingWeight/removeVotingWeight/vote are quite sensitive to token invariants. Caution is advised.
    constructor(DSToken PROT_, DSToken IOU_, uint MAX_CANDIDATES_PER_BALLOT_) public
    {
        PROT = PROT_;
        IOU = IOU_;
        MAX_CANDIDATES_PER_BALLOT = MAX_CANDIDATES_PER_BALLOT_;
    }

    function addVotingWeight(uint wad)
        public
    {
        PROT.pull(msg.sender, wad);
        IOU.mint(msg.sender, wad);
        deposits[msg.sender] = add(deposits[msg.sender], wad);
        addWeight(wad, votes[msg.sender]);
        emit AddVotingWeight(msg.sender, wad);
    }

    function removeVotingWeight(uint wad)
        public
    {
        deposits[msg.sender] = sub(deposits[msg.sender], wad);
        subWeight(wad, votes[msg.sender]);
        IOU.burn(msg.sender, wad);
        PROT.push(msg.sender, wad);
        emit RemoveVotingWeight(msg.sender, wad);
    }

    function groupCandidates(address[] memory candidates)
        public
        returns (bytes32 ballot)
    {
        require( candidates.length <= MAX_CANDIDATES_PER_BALLOT );
        requireByteOrderedSet(candidates);

        bytes32 _hash = keccak256(abi.encodePacked(candidates));
        ballots[_hash] = candidates;
        emit GroupCandidates(candidates, _hash);
        return _hash;
    }

    function vote(address[] memory candidates) public returns (bytes32)
        // note  both sub-calls note
    {
        bytes32 ballot = groupCandidates(candidates);
        vote(ballot);
        emit Vote(msg.sender, candidates, ballot);
        return ballot;
    }

    function vote(bytes32 ballot)
        public
    {
        require(ballots[ballot].length > 0 ||
            ballot == 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470, "ds-vote-quorum-invalid-ballot");
        uint weight = deposits[msg.sender];
        subWeight(weight, votes[msg.sender]);
        votes[msg.sender] = ballot;
        addWeight(weight, votes[msg.sender]);
        emit Vote(msg.sender, ballot);
    }

    function electCandidate(address whom)
        public
    {
        require(approvals[whom] > approvals[votedAuthority]);
        votedAuthority = whom;
        emit ElectCandidate(msg.sender, whom);
    }

    function addWeight(uint weight, bytes32 ballot)
        internal
    {
        address[] storage candidates = ballots[ballot];
        for( uint i = 0; i < candidates.length; i++) {
            approvals[candidates[i]] = add(approvals[candidates[i]], weight);
        }
    }

    function subWeight(uint weight, bytes32 ballot)
        internal
    {
        address[] storage candidates = ballots[ballot];
        for( uint i = 0; i < candidates.length; i++) {
            approvals[candidates[i]] = sub(approvals[candidates[i]], weight);
        }
    }

    // Throws unless the array of addresses is a ordered set.
    function requireByteOrderedSet(address[] memory candidates)
        internal
        pure
    {
        if( candidates.length == 0 || candidates.length == 1 ) {
            return;
        }
        for( uint i = 0; i < candidates.length - 1; i++ ) {
            // strict inequality ensures both ordering and uniqueness
            require(uint(candidates[i]) < uint(candidates[i+1]));
        }
    }
}


// `votedAuthority` address is unique root user (has every role) and the
// unique owner of role 0 (typically 'sys' or 'internal')
contract VoteQuorum is DSRoles, VoteQuorumApprovals {

    constructor(DSToken PROT, DSToken IOU, uint MAX_CANDIDATES_PER_BALLOT)
             VoteQuorumApprovals (PROT, IOU, MAX_CANDIDATES_PER_BALLOT)
        public
    {
        authority = this;
        owner = address(0);
    }

    function setOwner(address owner_) override public {
        owner_;
        revert();
    }

    function setAuthority(DSAuthority authority_) override public {
        authority_;
        revert();
    }

    function isUserRoot(address who)
        override
        public
        view
        returns (bool)
    {
        return (who == votedAuthority);
    }
    function setRootUser(address who, bool enabled) override public {
        who; enabled;
        revert();
    }
}

contract VoteQuorumFactory {
    event NewVoteQuorum(address gov, address iou, address voteQuorum, uint MAX_CANDIDATES_PER_BALLOT);

    function newVoteQuorum(DSToken gov, uint MAX_CANDIDATES_PER_BALLOT) public returns (VoteQuorum voteQuorum) {
        DSToken iou = new DSToken('IOU', 'IOU');
        voteQuorum = new VoteQuorum(gov, iou, MAX_CANDIDATES_PER_BALLOT);
        iou.setOwner(address(voteQuorum));
        emit NewVoteQuorum(address(gov), address(iou), address(voteQuorum), MAX_CANDIDATES_PER_BALLOT);
    }
}
