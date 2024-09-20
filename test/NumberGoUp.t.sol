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
   uint256 public maxTotalSupplyERC20 = 100000; // Stored in the contract as the ERC20 representation which is (n * 10^18)

   // Runs before each test case is run. 
   function setUp() public {
      numberGoUp = new NumberGoUp(
         "NumberGoUp", // Name
         "NGU", // Symbol
         decimals, // Decimals
         maxTotalSupplyERC20, // Max total supply
         owner, // Initial Owner
         owner, // Initial mint recipient
         exemptAddress, // Uniswap swap router
         exemptAddress // Uniswap NFPM
      );

      vm.prank(owner);
   }

   function testInitialState() public view {
      // Check Constructor
      assertEq(numberGoUp.name(), "NumberGoUp");
      assertEq(numberGoUp.symbol(), "NGU");
      assertEq(numberGoUp.decimals(), 18);
      assertEq(numberGoUp.erc20TotalSupply(), maxTotalSupplyERC20 * (10 ** decimals));
      // Expect no 721 tokens minted due to exempt status of owner. 
      assertEq(numberGoUp.erc721TotalSupply(), 0);
      // Check initial balances of owner and recipient
      assertEq(numberGoUp.balanceOf(owner), maxTotalSupplyERC20 * (10 ** decimals));
      assertEq(numberGoUp.balanceOf(recipient), 0);
   }

   function testTransfer5TokensFromOwner() public {
      // Transfer 5 tokens to recipient
      numberGoUp.transfer(recipient, 5 * (10 ** decimals));
      assertEq(numberGoUp.erc20BalanceOf(recipient), 5 * (10 ** decimals));

      // Check for minted NFTs owned by recipient
      assertEq(numberGoUp.erc721TotalSupply(), 5);
      assertEq(numberGoUp.erc721BalanceOf(recipient), 5);
      assertEq(numberGoUp.ownerOf(1), recipient);
      assertEq(numberGoUp.ownerOf(5), recipient);
   }

   function testStakeNFT() public {
      testTransfer5TokensFromOwner();
      // Stake NFT
      vm.prank(recipient);
      numberGoUp.stakeNFT(1);
      assertEq(numberGoUp.erc721BalanceOf(recipient), 4);
      assertEq(numberGoUp.getStakedERC20Balance(recipient), 1 * (10 ** decimals));

   }
}
