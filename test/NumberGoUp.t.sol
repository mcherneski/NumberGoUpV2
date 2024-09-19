//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {Test} from 'forge-std/Test.sol';
import "../src/NumberGoUp.sol";


contract NumberGoUpTest is Test {
   NumberGoUp public numberGoUp;

   address public owner = address(1);
   address public recipient = address(2);
   address public exemptAddress = address(3);
   address public nonExemptAddress = address(4);

   uint8 public decimals = 18;
   uint256 public totalSupply = 100000 * 10 ** decimals;


   // Runs before each test case is run. 
   function setUp() public {
      numberGoUp = new NumberGoUp("NumberGoUp", "NGU", decimals, totalSupply, owner, owner, exemptAddress, exemptAddress);

      vm.prank(owner);
      
   }

/// Runs as a test case for specific function. 
   function test_Numberis42() public {

   }
/// If function does not revert, it fails. 
   function testFail_Subtract43() public {
   
   }


}