// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "src/types/ERC20Asset.sol";

contract Tester {

    function unwrapAsset(ERC20Asset asset) public pure returns (address) {
        return ERC20Asset.unwrap(asset);
    }
}

contract ERC20AssetTest is Test {

    function testUnwrap() public {
        Tester tester = new Tester();
        tester.unwrapAsset(ERC20Asset.wrap(address(this)));
    }

}