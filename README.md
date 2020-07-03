# ds-vote-quorum

## Summary

This contract provides a way to elect a lead contract via approval voting.
This may be combined with another contract, such as `DSAuthority`, to elect a
ruleset for a smart contract system.

Voters lock up voting tokens to give their votes weight. The voting mechanism is
[approval voting](https://en.wikipedia.org/wiki/Approval_voting). Users get IOU
tokens any time they lock voting tokens, which is useful for secondary governance mechanisms.
The IOU tokens may not be exchanged for the locked tokens except by someone who
has actually locked funds in the contract, and only up to the amount they have locked.

Check out the full documentation [here](https://docs.reflexer.finance/).
