// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

contract BaseTest is Test {
    bool private s_baseTestInitialized;
    address internal constant LEADERNODE = 0xBcd4042DE499D14e55001CcbB24a551F3b954096;
    address[] public s_operatorAddresses;
    uint256[] public s_operatorPrivateKeys;
    mapping(address => uint256) public s_privateKeys;

    function setUp() public virtual {
        // BaseTest.setUp is often called multiple times from tests' setUp due to inheritance
        if (s_baseTestInitialized) return;
        s_baseTestInitialized = true;

        // Set msg.sender to LEADERNODE until changePrank or stopPrank is called
        vm.startPrank(LEADERNODE);
        vm.deal(LEADERNODE, 10000 ether);
    }

    function setOperatorAdresses(uint256 num) public {
        for (uint256 i; i < num; i++) {
            (address addr, uint256 key) = makeAddrAndKey(string(abi.encode(i)));
            s_operatorAddresses.push(addr);
            s_operatorPrivateKeys.push(key);
            s_privateKeys[addr] = s_operatorPrivateKeys[i];
            vm.deal(addr, 10000 ether);
        }
    }

    function mine(uint256 second) public {
        vm.warp(block.timestamp + second);
        vm.roll(block.number + 1);
    }
}
