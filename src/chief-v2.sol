pragma solidity >=0.5.0;

import "ds-note/note.sol";

contract TokenLike {
    function transferFrom(address, address, uint) public returns (bool);
}

contract Chief is DSNote {
    // --- Init ---
    constructor(address gov_) public { 
        gov = TokenLike(gov_); 
        threshold = ONE / 2;
    }

    // --- Math ---
    uint256 constant ONE = 10 ** 18;
    function add(uint x, uint y) internal pure returns (uint z) {
        z = x + y;
        require(z >= x);
    }
    function sub(uint x, uint y) internal pure returns (uint z) {
        z = x - y;
        require(z <= x);
    }
    function wmul(uint x, uint y) internal pure returns (uint z) {
        z = x * y;
        require(y == 0 || z / y == x);
        z = z / ONE;
    }

    // --- Data ---
    uint256 public threshold; // locked % needed to enact a proposal
    TokenLike public  gov; // governance token
    uint256 public locked; // total locked gov
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
        require(gov.transferFrom(msg.sender, address(this), wad));
        balances[msg.sender] = add(balances[msg.sender], wad);
        locked = add(locked, wad);

        bytes32 currPick = picks[msg.sender];
        if (currPick != bytes32(0) && !hasFired[currPick])
            votes[currPick] = add(votes[currPick], wad);
    }
    function free(uint256 wad) public note {
        balances[msg.sender] = sub(balances[msg.sender], wad);
        require(gov.transferFrom(address(this), msg.sender, wad));
        locked = sub(locked, wad);

        bytes32 currPick = picks[msg.sender];
        if (currPick != bytes32(0) && !hasFired[currPick])
            votes[currPick] = sub(votes[currPick], wad);
    }
    function vote(bytes32 currPick) public {
        require(!hasFired[currPick]);        

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
        require(!hasFired[proposal]);
        require(votes[proposal] > wmul(locked, threshold));

        assembly {
            let ok := delegatecall(sub(gas, 5000), app, add(data, 0x20), mload(data), 0, 0)
            if eq(ok, 0) { revert(0, 0) }
        }

        hasFired[proposal] = true;
        emit Executed(msg.sender, proposal, app, data);
    }
}
