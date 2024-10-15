//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {Test} from 'forge-std/Test.sol';
import {console} from "forge-std/console.sol";
import "../src/NumberGoUp.sol";


contract NumberGoUpTest is Test {
   NumberGoUp public numberGoUp;

   address public owner = address(1);
   address public recipient = address(2);
   address public recipientTwo = address(5);
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

   function testSetERC721TransferExempt() public {
      numberGoUp.setERC721TransferExempt(exemptAddress, true);
      bool isExempt = numberGoUp.erc721TransferExempt(exemptAddress);
      assertTrue(isExempt);
   }

   function testTransferTokensFromOwner() public {
      // Transfer 5 tokens to recipient
      numberGoUp.transfer(recipient, 5 * (10 ** decimals));
      assertEq(numberGoUp.erc20BalanceOf(recipient), 5 * (10 ** decimals));
      // Check for minted NFTs owned by recipient
      assertEq(numberGoUp.erc721TotalSupply(), 5);
      assertEq(numberGoUp.erc721BalanceOf(recipient), 5);
      assertEq(numberGoUp.ownerOf(1), recipient);
      assertEq(numberGoUp.ownerOf(5), recipient);
      // Check that ID 1 is the next in the selling queue
      assertEq(numberGoUp.getNextQueueId(recipient), 1);
      // assertEq(numberGoUp.getERC721TokensInQueue(recipient, 10), [1]);
   }


/// @notice - Staking: 
/// Tests: 
/// 1. Require ERC-721 balance
/// 2. Require ERC-20 balance
/// 3. Staker has ERC-20 removed from balance, added to bank
/// 4. ID is removed from Selling queue
/// 5. Add ID to staked stack
/// 6. Staked data updated
   function testStakeNFTRequirements() public {
      // Setup
      numberGoUp.transfer(recipient, 5 * (10 ** decimals));

      // Test ERC-721 balance requirement
      vm.prank(recipient);
      vm.expectRevert();
      numberGoUp.stakeNFT(6);  // Trying to stake a non-existent token

      // Test ERC-20 balance requirement
      vm.startPrank(recipient);
      numberGoUp.transfer(address(1), 5 * (10 ** decimals));  // Transfer all ERC-20 tokens away
      vm.expectRevert();
      numberGoUp.stakeNFT(1);
      vm.stopPrank();
   }

   function testStakeNFTLogic() public {
      // Setup
      numberGoUp.transfer(recipient, 5 * (10 ** decimals));
      uint256 initialERC20Balance = numberGoUp.erc20BalanceOf(recipient);
      uint256 initialERC721Balance = numberGoUp.erc721BalanceOf(recipient);

      vm.startPrank(recipient);
      
      // Stake NFT
      numberGoUp.stakeNFT(1);

      // Check ERC-20 balance reduced
      assertEq(numberGoUp.erc20BalanceOf(recipient), initialERC20Balance - 1 * (10 ** decimals));
      
      // Check ERC-20 added to staked bank
      assertEq(numberGoUp.getStakedERC20Balance(recipient), 1 * (10 ** decimals));

      // Check ID removed from selling queue
      uint256[] memory queuedTokens = numberGoUp.getERC721TokensInQueue(recipient, 10);
      for (uint i = 0; i < queuedTokens.length; i++) {
         assertFalse(queuedTokens[i] == 1);
      }

      // Check ID added to staked stack
      uint256[] memory stakedTokens = numberGoUp.getStakedTokens(recipient);
      assertEq(stakedTokens[0], 1);

      // Check staked data updated
      assertEq(numberGoUp.erc721BalanceOf(recipient), initialERC721Balance);

      vm.stopPrank();
   }

   function testUnstakeNFTOwnershipRequirement() public {
      // Setup
      numberGoUp.transfer(recipient, 5 * (10 ** decimals));
      vm.prank(recipient);
      numberGoUp.stakeNFT(1);

      // Test ownership requirement
      vm.expectRevert();
      numberGoUp.unStakeNFT(1);
   }

   function testUnstakeNFTStakedTokenRequirement() public {
      // Setup
      numberGoUp.transfer(recipient, 5 * (10 ** decimals));

      // Test unstaking a token that hasn't been staked
      vm.prank(recipient);
      vm.expectRevert();
      numberGoUp.unStakeNFT(1);
   }

   function testUnstakeNFTLogic() public {
      // Setup
      numberGoUp.transfer(recipient, 5 * (10 ** decimals));
      vm.startPrank(recipient);
      numberGoUp.stakeNFT(1);
      uint256 initialERC20Balance = numberGoUp.erc20BalanceOf(recipient);
      uint256 initialStakedBalance = numberGoUp.getStakedERC20Balance(recipient);
      uint256 initialQueueLength = numberGoUp.getERC721TokensInQueue(recipient, 10).length;

      // Unstake NFT
      numberGoUp.unStakeNFT(1);

      // Check ERC-20 retrieved from staked bank
      assertEq(numberGoUp.getStakedERC20Balance(recipient), initialStakedBalance - 1 * (10 ** decimals));

      // Check ERC-20 added to balance
      assertEq(numberGoUp.erc20BalanceOf(recipient), initialERC20Balance + 1 * (10 ** decimals));

      // Check ID added back to selling queue
      assertEq(numberGoUp.getERC721TokensInQueue(recipient, 10).length, initialQueueLength + 1);

      // Check ID removed from staked array
      uint256[] memory stakedTokens = numberGoUp.getStakedTokens(recipient);
      for (uint i = 0; i < stakedTokens.length; i++) {
         assertFalse(stakedTokens[i] == 1);
      }

      vm.stopPrank();
   }

   // function testStakeNFT() public {
   //    testTransferTokensFromOwner();
   //    uint8 testBalance = 5;
   //    // Stake NFT
   //    vm.prank(recipient);
   //    numberGoUp.stakeNFT(1);
   //    assertEq(numberGoUp.erc721BalanceOf(recipient), testBalance);
   //    assertEq(numberGoUp.getStakedERC20Balance(recipient), 1 * (10 ** decimals));
   //    // Make sure NFT IDs are removed from queue.
   //    assertEq(numberGoUp.getERC721TokensInQueue(recipient, 10).length, testBalance - 1);
   //    // Make sure the _staked is correct.
   //    assertEq(numberGoUp.getStakedTokens(recipient).length, 1);
   // }

   // function testUnstakeNFT() public {
   //    testStakeNFT();
   //    vm.prank(recipient);
   //    numberGoUp.unStakeNFT(1);
   //    assertEq(numberGoUp.getERC721TokensInQueue(recipient, 10).length, 5);
   //    assertEq(numberGoUp.getStakedTokens(recipient).length, 0);
   //    assertEq(numberGoUp.getStakedERC20Balance(recipient), 0);
   // }

   function testTransferTokensBetweenNonOwnerAddresses() public {
      // Initial setup
      uint256 initialOwnerBalance = numberGoUp.erc20BalanceOf(owner);
      uint256 transferAmount = 5 * (10 ** decimals);
      vm.prank(owner);
      // Transfer from owner to recipient
      numberGoUp.transfer(recipient, transferAmount);
      assertEq(numberGoUp.erc20BalanceOf(owner), initialOwnerBalance - transferAmount);
      assertEq(numberGoUp.erc20BalanceOf(recipient), transferAmount);
      assertEq(numberGoUp.erc721BalanceOf(recipient), 5);

      // Transfer from recipient to recipientTwo
      uint256 secondTransferAmount = 2 * (10 ** decimals);
      vm.prank(recipient);
      numberGoUp.transfer(recipientTwo, secondTransferAmount);

      // Check ERC20 balances
      assertEq(numberGoUp.erc20BalanceOf(recipient), transferAmount - secondTransferAmount);
      assertEq(numberGoUp.erc20BalanceOf(recipientTwo), secondTransferAmount);

      // Check ERC721 balances
      assertEq(numberGoUp.erc721BalanceOf(recipient), 3);
      assertEq(numberGoUp.erc721BalanceOf(recipientTwo), 2);

      // Check total supply remains constant
      assertEq(numberGoUp.totalSupply(), initialOwnerBalance);

      // Check specific token ownership
      assertEq(numberGoUp.ownerOf(1), recipient);
      assertEq(numberGoUp.ownerOf(2), recipient);
      assertEq(numberGoUp.ownerOf(3), recipient);
      // assertEq(numberGoUp.ownerOf(4), recipientTwo);
      // assertEq(numberGoUp.ownerOf(5), recipientTwo);

      // Try to transfer more than balance
      vm.prank(recipient);
      vm.expectRevert("Insufficient balance");
      numberGoUp.transfer(recipientTwo, 4 * (10 ** decimals));

      // Check balances remain unchanged after failed transfer
      assertEq(numberGoUp.erc20BalanceOf(recipient), 3 * (10 ** decimals));
      assertEq(numberGoUp.erc20BalanceOf(recipientTwo), 2 * (10 ** decimals));
   }
}
