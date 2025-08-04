// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "forge-std/Test.sol";

contract BaseTest is Test {
    bool private s_baseTestInitialized;
    address internal constant LEADERNODE = 0xBcd4042DE499D14e55001CcbB24a551F3b954096;
    address[] public s_operatorAddresses;
    uint256[] public s_operatorPrivateKeys;
    mapping(address => uint256) public s_privateKeys;
    string public s_gasReportPath;
    string public s_gasObject = "gas report";

    function setUp() public virtual {
        // BaseTest.setUp is often called multiple times from tests' setUp due to inheritance
        if (s_baseTestInitialized) return;
        s_baseTestInitialized = true;
        vm.deal(LEADERNODE, 10000 ether);
        string memory root = vm.projectRoot();
        s_gasReportPath = string.concat(root, "/output/gasreport.json");
        if (!vm.exists(s_gasReportPath)) {
            vm.writeFile(s_gasReportPath, "{}");
        }
    }

    function setOperatorAddresses(uint256 num) public {
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

    function _getAverageExceptIndex0(uint256[] memory arr) internal pure returns (uint256) {
        uint256 sum;
        uint256 len = arr.length;
        for (uint256 i = 1; i < len; i++) {
            sum += arr[i];
        }
        return sum / (len - 1);
    }

    function _getMaxExceptIndex0(uint256[] memory arr) internal pure returns (uint256) {
        uint256 max = arr[1];
        uint256 len = arr.length;
        for (uint256 i = 2; i < len; i++) {
            max = max > arr[i] ? max : arr[i];
        }
        return max;
    }

    function _consoleAverageExceptIndex0(uint256[] memory arr, string memory msg1) internal pure {
        console2.log(msg1, _getAverageExceptIndex0(arr));
    }
}
