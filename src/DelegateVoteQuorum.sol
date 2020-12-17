// Copyright 2020 Compound Labs, Inc.
//
// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
//
// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
//
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
//
// 3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; // OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

pragma solidity 0.6.7;
pragma experimental ABIEncoderV2;

import "ds-token/token.sol";
import 'ds-roles/roles.sol';

interface DSDelegateTokenLike {
    function totalSupply() external view returns (uint);
    function getPriorVotes(address account, uint blockNumber) external view returns (uint256);
}

interface DSRolesLike {
    function setRootUser(address, bool) external;
    function isUserRoot(address) external view returns (bool);
}

interface DSPauseLike {
    function proxy() external view returns (address);
    function delay() external view returns (uint);
    function scheduleTransaction(address, bytes32, bytes calldata, uint) external;
    function abandonTransaction(address, bytes32, bytes calldata, uint) external;
    function authority() external view returns (address);
}

contract SetUserRootProposal {
    function setRootUser(DSRolesLike target, address account, bool isRoot) public {
        target.setRootUser(account, isRoot);
    }
}

contract DelegateVoteQuorum {
    /// @notice The name of this contract
    string                     public name;
    /// @notice The number of votes in support of a proposal required in order for a quorum to be reached and for a vote to succeed
    uint256                    public quorumVotes;
    /// @notice The number of votes required in order for a voter to become a proposer
    uint256                    public proposalThreshold;
    /// @notice The duration of voting on a proposal, in blocks
    uint256                    public votingPeriod;
    /// @notice The delay before voting on a proposal may take place, once proposed
    uint256                    public votingDelay = 1;
    /// @notice Total lifetime for a proposal from the moment it's proposed (in blocks)
    uint256                    public proposalLifetime;
    /// @notice The address of the Governor Guardian
    address                    public guardian;
    /// @notice The total number of proposals
    uint256                    public proposalCount;
    /// @notice The official record of all proposals ever proposed
    mapping (uint => Proposal) public proposals;
    /// @notice The latest proposal for each proposer
    mapping (address => uint)  public latestProposalIds;
    /// @notice The address of the protocol token
    DSDelegateTokenLike        public protocolToken;
    /// @notice The address of DSPause
    DSPauseLike                public pause;

    struct Proposal {
        /// @notice Unique id for looking up a proposal
        uint id;
        /// @notice Type of the proposal
        ProposalType proposalType;
        /// @notice Creator of the proposal
        address proposer;
        /// @notice the target addresses for the call to be made
        address target;
        /// @notice The destination of the call (proposal address)
        address usr;
        /// @notice The codeHash of the destination
        bytes32 codeHash;
        /// @notice The calldata to be passed to the call
        bytes data;
        /// @notice The block at which voting begins: holders must delegate their votes prior to this block
        uint startBlock;
        /// @notice The block at which voting ends: votes must be cast prior to this block
        uint voteEndBlock;
        /// @notice The block at which the proposal lifetime ends and it's considered expired
        uint lifetimeEndBlock;
        /// @notice Current number of votes in favor of this proposal
        uint forVotes;
        /// @notice Current number of votes in opposition to this proposal
        uint againstVotes;
        /// @notice Flag marking whether the proposal has been canceled
        bool canceled;
        /// @notice Flag marking whether the proposal has been scheduled in DSPause
        bool scheduled;
        /// @notice Receipts of ballots for the entire set of voters
        mapping (address => Receipt) receipts;
    }
    /// @notice Ballot receipt record for a voter
    struct Receipt {
        /// @notice Whether or not a vote has been cast
        bool hasVoted;
        /// @notice Whether or not the voter supports the proposal
        bool support;
        /// @notice The number of votes the voter had, which were cast
        uint256 votes;
    }

    /// @notice Possible states that a proposal may be in
    enum ProposalState {
        Pending,
        Active,
        Canceled,
        Defeated,
        Succeeded,
        Expired,
        Executed,
        Null
    }

    /// @notice Possible types of proposal
    enum ProposalType {
        Abandon,
        Schedule,
        Arbitrary
    }

    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");
    /// @notice The EIP-712 typehash for the ballot struct used by the contract
    bytes32 public constant BALLOT_TYPEHASH = keccak256("Ballot(uint256 proposalId,bool support)");

    /// @notice An event emitted when a new proposal is created
    event ProposalCreated(uint id, address proposer, address target, bytes data, uint startBlock, uint voteEndBlock, uint lifetimeEndBlock, string description);
    /// @notice An event emitted when a vote has been cast on a proposal
    event VoteCast(address voter, uint proposalId, bool support, uint votes);
    /// @notice An event emitted when a proposal has been executed in DSPause
    event ProposalExecuted(uint id);
    /// @notice An event emitted when a proposal has been canceled
    event ProposalCanceled(uint id);
    /// @notice An event emitted when a parameter has been modified
    event ModifyParameters(bytes32 parameter, address value);

    constructor(
      string memory name_,
      uint256 quorumVotes_,
      uint256 proposalThreshold_,
      uint256 votingPeriod_,
      uint256 proposalLifetime_,
      address pauseAddress,
      address guardianAddress
    ) public {
        require(quorumVotes_ > 0, "DelegateVoteQuorum/invalid-quorum-votes");
        require(proposalThreshold_ > 0, "DelegateVoteQuorum/invalid-proposal-threshold");
        require(votingPeriod_ > 0, "DelegateVoteQuorum/invalid-voting-period");
        require(proposalLifetime_ > votingPeriod_, "DelegateVoteQuorum/invalid-proposal-lifetime");
        pause                          = DSPauseLike(pauseAddress);
        name                           = name_;
        quorumVotes                    = quorumVotes_;
        proposalLifetime               = proposalLifetime_;
        proposalThreshold              = proposalThreshold_;
        votingPeriod                   = votingPeriod_;
        guardian                       = guardianAddress;
    }

    // --- Auth ---
    // @notice Reverts if msg.sender is not the guardian
    modifier isGuardian {
        require(msg.sender == guardian, "DelegateVoteQuorum/account-not-authorized");
        _;
    }

    // --- Admin ---
    /**
     * @notice Modifies an address parameter
     * @param value Parameter new value
     */
    function modifyParameters(bytes32 parameter, address value) external isGuardian {
        if (parameter == "protocolToken") {
            require(address(protocolToken) == address(0), "DelegateVoteQuorum/protocol-token-already-set");
            protocolToken = DSDelegateTokenLike(value);
            require(both(quorumVotes < protocolToken.totalSupply(), proposalThreshold < protocolToken.totalSupply()), "DelegateVoteQuorum/invalid-total-supply");
        } else revert("DelegateVoteQuorum/modify-unrecognized-param");
        emit ModifyParameters(parameter, value);
    }

    // --- Util ---
    function extcodehash(address who) public view returns (bytes32 codehash) {
        assembly { codehash := extcodehash(who) }
    }

    function getChainId() internal pure returns (uint) {
        uint chainId;
        assembly { chainId := chainid() }
        return chainId;
    }

    // --- Boolean Logic ---
    function both(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := and(x, y)}
    }

    function either(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := or(x, y)}
    }

    // --- Math ---
    function add256(uint256 a, uint256 b) internal pure returns (uint) {
        uint c = a + b;
        require(c >= a, "DelegateVoteQuorum/addition-overflow");
        return c;
    }

    function sub256(uint256 a, uint256 b) internal pure returns (uint) {
        require(b <= a, "DelegateVoteQuorum/subtraction-underflow");
        return a - b;
    }

    // --- Core Logic ---
    /// @notice Create a proposal
    /// @param proposalType ProposalType
    /// @param proposalAddress Address of the proposal execution contract
    /// @param proposalHash Extcodehash of the proposal execution contract
    /// @param data Calldata for the call to the proposal contract
    /// @param description Description of the proposal
    /// @return Proposal Id
    function propose(ProposalType proposalType, address proposalAddress, bytes32 proposalHash, bytes memory data, string memory description) public returns (uint) {
        require(protocolToken.getPriorVotes(msg.sender, sub256(block.number, 1)) > proposalThreshold, "DelegateVoteQuorum/proposer-votes-below-threshold");
        require(extcodehash(proposalAddress) == proposalHash, "DelegateVoteQuorum/code-hash-does-not-match-target");

        uint latestProposalId = latestProposalIds[msg.sender];
        if (latestProposalId != 0) {
          ProposalState proposersLatestProposalState = state(latestProposalId);
          require(proposersLatestProposalState != ProposalState.Active, "DelegateVoteQuorum/already-active-proposal");
          require(proposersLatestProposalState != ProposalState.Pending, "DelegateVoteQuorum/already-pending-proposal");
        }

        uint startBlock       = add256(block.number, votingDelay);
        uint voteEndBlock     = add256(startBlock, votingPeriod);
        uint lifetimeEndBlock = add256(startBlock, proposalLifetime);

        proposalCount++;
        Proposal memory newProposal = Proposal({
            id: proposalCount,
            proposalType: proposalType,
            proposer: msg.sender,
            target: address(pause),
            usr: proposalAddress,
            codeHash: proposalHash,
            data: data,
            startBlock: startBlock,
            voteEndBlock: voteEndBlock,
            lifetimeEndBlock: lifetimeEndBlock,
            forVotes: 0,
            againstVotes: 0,
            canceled: false,
            scheduled: false
        });

        proposals[newProposal.id]               = newProposal;
        latestProposalIds[newProposal.proposer] = newProposal.id;

        emit ProposalCreated(newProposal.id, msg.sender, address(pause), data, startBlock, voteEndBlock, lifetimeEndBlock, description);
        return newProposal.id;
    }

    /// @notice Create a proposal
    /// @param proposalId Id of the (succeeded) proposal to be executed
    function execute(uint proposalId) public {
        require(state(proposalId) == ProposalState.Succeeded, "DelegateVoteQuorum/proposal-not-succeeded");
        Proposal storage proposal = proposals[proposalId];
        proposal.scheduled = true;
        if (proposal.proposalType == ProposalType.Schedule) {
            pause.scheduleTransaction(proposal.usr, proposal.codeHash, proposal.data, block.timestamp + pause.delay());
        } else if (proposal.proposalType == ProposalType.Abandon) {
            pause.abandonTransaction(proposal.usr, proposal.codeHash, proposal.data, block.timestamp + pause.delay());
        } else if (proposal.proposalType == ProposalType.Arbitrary) {
            require(both(proposal.usr != address(pause.authority()), proposal.usr != address(pause)), "DelegateVoteQuorum/arbitrary-calls-to-pause-not-allowed");
            (bool success, ) = address(proposal.usr).call(proposal.data);
            require(success, "DelegateVoteQuorum/unsuccessful-call");
        }
        emit ProposalExecuted(proposalId);
    }

    /// @notice Cancel a proposal
    /// @param proposalId Id of the (succeeded) proposal to be executed
    function cancel(uint proposalId) public {
        ProposalState state = state(proposalId);
        require(state != ProposalState.Executed, "DelegateVoteQuorum/cannot-cancel-executed-proposal");

        Proposal storage proposal = proposals[proposalId];
        require(msg.sender == guardian || protocolToken.getPriorVotes(proposal.proposer, sub256(block.number, 1)) < proposalThreshold, "DelegateVoteQuorum/proposer-above-threshold");
        proposal.canceled = true;

        emit ProposalCanceled(proposalId);
    }

    /// @notice Get voter receipt for a given proposal
    /// @param proposalId Id of the proposal
    /// @param voter Address of the voter
    /// @return Receipt
    function getReceipt(uint proposalId, address voter) public view returns (Receipt memory) {
        return proposals[proposalId].receipts[voter];
    }

    /// @notice Returns state of a proposal
    /// @param proposalId Id of the proposal
    /// @return ProposalState
    function state(uint proposalId) public view returns (ProposalState) {
        require(proposalCount >= proposalId && proposalId > 0, "DelegateVoteQuorum/invalid-proposal-id");
        Proposal storage proposal = proposals[proposalId];
        
        if (block.number <= proposal.startBlock) {
            return ProposalState.Pending;
        } else if (block.number <= proposal.voteEndBlock) {
            return ProposalState.Active;
        } else if (proposal.forVotes <= proposal.againstVotes || proposal.forVotes < quorumVotes) {
            return ProposalState.Defeated;
        } else if (proposal.scheduled) {
            return ProposalState.Executed;
        } else if (block.number >= proposal.lifetimeEndBlock) {
            return ProposalState.Expired;
        } else if (both(proposal.forVotes > proposal.againstVotes, proposal.forVotes >= quorumVotes)) {
            return ProposalState.Succeeded;
        } else {
            return ProposalState.Null;
        }
    }

    /// @notice Casts a vote
    /// @param proposalId Id of the proposal
    /// @param support True for a pro proposal vote, false for a con vote
    function castVote(uint proposalId, bool support) public {
        return _castVote(msg.sender, proposalId, support);
    }

    /// @notice Casts a meta vote (signed offline, params v, r and s)
    /// @param proposalId Id of the proposal
    /// @param support True for a pro proposal vote, false for a con vote
    function castVoteBySig(uint proposalId, bool support, uint8 v, bytes32 r, bytes32 s) public {
        bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name)), getChainId(), address(this)));
        bytes32 structHash = keccak256(abi.encode(BALLOT_TYPEHASH, proposalId, support));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), "DelegateVoteQuorum/invalid-signature");
        return _castVote(signatory, proposalId, support);
    }

    /// @notice Casts a vote (internal)
    /// @param voter Address of voter
    /// @param proposalId Id of the proposal
    /// @param support True for a pro proposal vote, false for a con vote
    function _castVote(address voter, uint proposalId, bool support) internal {
        require(state(proposalId) == ProposalState.Active, "DelegateVoteQuorum/voting-is-closed");
        Proposal storage proposal = proposals[proposalId];
        Receipt storage receipt = proposal.receipts[voter];
        require(receipt.hasVoted == false, "DelegateVoteQuorum/voter-already-voted");
        uint256 votes = protocolToken.getPriorVotes(voter, proposal.startBlock);

        if (support) {
            proposal.forVotes = add256(proposal.forVotes, votes);
        } else {
            proposal.againstVotes = add256(proposal.againstVotes, votes);
        }
        receipt.hasVoted = true;
        receipt.support  = support;
        receipt.votes    = votes;

        emit VoteCast(voter, proposalId, support, votes);
    }


    // Guardian Functions
    /// @notice Abdicates the guardian role (onlyGuardian)
    function abdicate() public isGuardian {
        guardian = address(0);
    }

    /// @notice Transfers root access from this contract to another one (onlyGuardian)
    /// @param account Account to become root in dspause.authority()
    /// @return revokeProposal Address of the proposal to revoke access from this contract
    /// @return grantProposal Address of the proposal to grant root access to address account
    function transferRootAccess(address account) public isGuardian returns (address revokeProposal, address grantProposal) {
        revokeProposal = _manageRootAccess(address(this), false);
        grantProposal  = _manageRootAccess(account, true);
    }

    /// @notice Grants root access to an account (onlyGuardian)
    /// @param account Account to become root in dspause.authority()
    /// @return proposal Address of the proposal
    function manageRootAccess(address account, bool isRoot) public isGuardian returns (address proposal) {
        proposal = _manageRootAccess(account, isRoot);
    }

    /// @notice Grants root access to an account (internal)
    /// @param account Account to become root in dspause.authority()
    /// @return proposal Address of the proposal
    function _manageRootAccess(address account, bool isRoot) internal returns (address proposal) {
        proposal = address(new SetUserRootProposal());
        address usr = proposal;
        bytes32 codeHash = extcodehash(usr);
        bytes memory data = abi.encodeWithSignature("setRootUser(address,address,bool)", pause.authority(), account, isRoot);
        pause.scheduleTransaction( proposal, codeHash, data, block.timestamp + pause.delay());
    }
}
