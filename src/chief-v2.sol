pragma solidity >=0.5.0;

import "ds-note/note.sol";
import "ds-math/math.sol";

contract TokenLike {
    function transferFrom(address, address, uint) public returns (bool);
}

contract Chief is DSNote, DSMath {
    // --- Init ---
    constructor(address governanceToken_) public { 
        governanceToken = TokenLike(governanceToken_); 
        threshold = WAD / 2;
    }

    // --- Data ---
    uint256 public threshold; // locked % needed to enact a proposal
    TokenLike public governanceToken; 
    uint256 public locked; // total locked governanceToken
    mapping(bytes32 =>    bool) public hasFired; // proposal => hasFired?
    mapping(address => uint256) public balances; // guy => lockedGovHowMuch
    mapping(address => bytes32) public picks; // guy => proposalHash
    mapping(bytes32 => uint256) public votes; // proposalHash => votesHowMany

    // --- Events ---
    event Voted(
        bytes32 indexed proposalHash,
        address indexed voter, 
        uint256 weight
    );
    event Executed(
        address caller,
        bytes32 proposal,
        address indexed app,
        bytes data
    );

    // --- Voting Interface ---
    function lock(uint256 wad) public note {
        require(governanceToken.transferFrom(msg.sender, address(this), wad), "ds-chief-transfer-failed");
        balances[msg.sender] = add(balances[msg.sender], wad);
        locked = add(locked, wad);

        bytes32 currPick = picks[msg.sender];
        if (currPick != bytes32(0) && !hasFired[currPick])
            votes[currPick] = add(votes[currPick], wad);
    }
    function free(uint256 wad) public note {
        balances[msg.sender] = sub(balances[msg.sender], wad);
        require(governanceToken.transferFrom( address(this), msg.sender, wad), "ds-chief-transfer-failed");
        locked = sub(locked, wad);

        bytes32 currPick = picks[msg.sender];
        if (currPick != bytes32(0) && !hasFired[currPick])
            votes[currPick] = sub(votes[currPick], wad);
    }

    function vote(bytes32 currPick) public {
        require(!hasFired[currPick], "ds-chief-propposal-has-already-been-enacted");        

        uint256 weight   = balances[msg.sender];
        bytes32 prevPick = picks[msg.sender];

        if (prevPick != bytes32(0) && !hasFired[prevPick])
            votes[prevPick] = sub(votes[prevPick], weight);

        votes[currPick]   = add(votes[currPick], weight);
        picks[msg.sender] = currPick;

        emit Voted(currPick, msg.sender, weight);
    }
    function exec(address app, bytes memory data) public {
        bytes32 proposal = keccak256(abi.encode(app, data));
        require(!hasFired[proposal], "ds-chief-propposal-has-already-been-enacted");
        require(votes[proposal] > wmul(locked, threshold), "ds-chief-proposal-does-not-pass-threshold");

        assembly {
            let ok := delegatecall(sub(gas, 5000), app, add(data, 0x20), mload(data), 0, 0)
            if eq(ok, 0) { revert(0, 0) }
        }

        hasFired[proposal] = true;
        emit Executed(msg.sender, proposal, app, data);
    }
}
