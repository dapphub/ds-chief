// action.sol - Action Hats for DSChief

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

