# ds-chief


## Summary

This contract provides a way to elect a "chief" via approval voting. This may be
combined with another contract, such as `DSAuthority`, to elect an autocratic
ruler over a smart contract system. Think of this as a
[ds-prism](https://github.com/dapphub/ds-prism) optimized for electing a group
of size 1.

Voters lock up voting tokens to give their votes weight. In return, they are
issued "IOU" tokens representing the tokens they have locked. The IOU tokens may
not be exchanged for the locked tokens except by someone who has actually locked
funds in the contract, and only up to the amount they have locked.


## Approval Voting

**Approval voting** is when each voter selects which candidates they approve of,
with the top `n` "most approved" candidates being elected. Each voter can cast
up to `n + k` votes, where `k` is some non-zero positive integer. This allows
voters to move their approval from one candidate to another without needing to
first withdraw support from the candidate being replaced. Without this, moving
approval to a new candidate could result in a less-approved candidate moving
momentarily into the set of elected candidates.

In the case of `ds-chief`, `n` is 1.

In addition, `ds-chief` weights votes according to the quantity of a voting
token they've chosen to lock up in the `DSChief` or `DSChiefApprovals` contract.

It's important to note that the voting token used in a `ds-chief` deployment
must be specified at the time of deployment and cannot be changed afterward.


## APIs

There are two contracts in `ds-chief`: `DSChiefApprovals` and `DSChief`, which
inherits from `DSChiefApprovals`.

`DSChiefApprovals` provides the following public properties:

- `slates`: A mapping of `bytes32` to `address` arrays. Represents sets of
  candidates. Weighted votes are given to slates.
- `votes`: A mapping of voter addresses to the slate they have voted for.
- `approvals`: A mapping of candidate addresses to their `uint128` weight.
- `deposits`: A mapping of voter addresses to `uint128` number of tokens locked.
- `GOV`: `DSToken` used for voting.
- `IOU`: `DSToken` issued in exchange for locking `GOV` tokens.
- `hat`: Contains the address of the current "chief."
- `MAX_YAYS`: Maximum number of candidates a slate can hold.

It also provides the following events:

- `LogLockFree(address indexed who, uint128 before, uint128 afterwards)`: Fired
  when a user locks or unlocks their `GOV` tokens.
- `LogEtch(bytes32 indexed slate)`: Fired when a slate is created.
- `LogVote(address indexed who, bytes32 indexed slate, uint128 before, uint128
  after)`: Fired when a user votes for a slate.
- `LogLift(address indexed hat_)`: Fired when a new chief is elected.


Its public functions are as follows:

### `DSChiefApprovals(DSToken GOV_, DSToken IOU_, uint MAX_YAYS_)`

The constructor.  Sets `GOV`, `IOU`, and `MAX_YAYS`.


### `lock(uint128 wad)`

Charges the user `wad` `GOV` tokens, issues an equal amount of `IOU` tokens to
the user, and adds `wad` weight to the candidates on the user's selected slate.
Fires a `LogLockFree` event.


### `free(uint128 wad)`

Charges the user `wad` `IOU` tokens, issues an equal amount of `GOV` tokens to
the user, and subtracts `wad` weight from the candidates on the user's selected
slate. Fires a `LogLockFree` event.


### `etch(address[] yays) returns (bytes32 slate)`

Save a set of ordered addresses and return a unique identifier for it.


### `vote(bytes32 slate)`

Removes voter's weight from their current slate and adds it to the specified
slate.


### `vote(bytes32 slate, address lift_whom)`

Calls `vote(bytes32 slate)` and then `lift(address whom)`.


### `lift(address whom)`

Checks the given address and promotes it to `chief` if it has more weight than
the current chief.


`DSChief` is a combination of `DSRoles` from the `ds-roles` package and
`DSChiefApprovals`. It can be used in conjunction with `ds-auth` to govern smart
contract systems.

Its public functions are as follows:


### `DSChief(DSToken GOV_, DSToken IOU_, uint MAX_YAYS_)`

The constructor.  Sets `GOV`, `IOU`, and `MAX_YAYS`.


### `getUserRoles(address who) constant returns (bytes32)`

Overrides `DSRoles.getUserRoles` to return the maximum `bytes32` value if the
address of the current chief is given. This means the chief has all roles.


### `isUserRoot(address who) constant returns (bool)`

Returns `true` if the given address is the chief, reverts to a normal `DSRoles`
check otherwise.


### `setUserRole(address who, uint8 role, bool enabled)`

Throws if `role` is `<= 0`, otherwise passes the call up to `DSRoles`.


### `setRootUser(address who, bool enabled)`

Ensures that the user is not trying to remove the `root` role from the "chief,"
then passes the call up to `DSRoles`.
