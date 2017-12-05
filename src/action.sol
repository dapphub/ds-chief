pragma solidity ^0.4.15;

import 'ds-thing/thing.sol';

contract ActionHat is DSThing {
    address public target;
    uint256 public value;
    bytes   public data;
    bool    public done;
    function ActionHat(address target_, uint256 value_, bytes data_) {
        target = target_;
        value = value_;
        data = data_;
    }
    function fire() auth { // TODO auth?
        require(!done);
        target.call.value(value)(data);
        done = true;
    }
}

contract ActionHatFactory {
    function make(address target, uint256 value, bytes data) returns (ActionHat) {
        var A = new ActionHat(target, value, data);
        A.setOwner(msg.sender);
        return A;
    }
}

