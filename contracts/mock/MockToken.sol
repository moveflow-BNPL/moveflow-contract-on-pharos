// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {

    constructor() ERC20("MockToken", "MockToken") {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}