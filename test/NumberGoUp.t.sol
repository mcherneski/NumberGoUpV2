//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {Test} from 'forge-std/Test.sol';
import {console} from "forge-std/console.sol";
import "../src/NumberGoUp.sol";


contract NumberGoUpTest is Test {
   NumberGoUp public numberGoUp;

   address public owner = address(1);
   address public user = address(2);
   address public user2 = address(5);
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
         owner, // Initial mint user
         exemptAddress, // Uniswap swap router
         exemptAddress // Uniswap NFPM
      );

      vm.prank(owner);
   }

   function testInitialState() public view {
      // Check Constructor
      assertEq(numberGoUp.name(), "NumberGoUp", "Name should be NumberGoUp");
      assertEq(numberGoUp.symbol(), "NGU", "Symbol should be NGU");
      assertEq(numberGoUp.decimals(), 18, "Decimals should be 18");
      assertEq(numberGoUp.erc20TotalSupply(), maxTotalSupplyERC20 * (10 ** decimals), "Total supply should be 100000 whole ERC20 tokens");

      // Expect no 721 tokens minted due to exempt status of owner. 
      assertEq(numberGoUp.erc721TotalSupply(), 0, "Total supply should be 0");

      // Check initial balances of owner and user
      assertEq(numberGoUp.balanceOf(owner), maxTotalSupplyERC20 * (10 ** decimals), "Owner should have 100000 whole ERC20 tokens");
      assertEq(numberGoUp.balanceOf(user), 0, "User should have 0 whole ERC20 tokens");
   }

   function testSetERC721TransferExempt() public {
      numberGoUp.setERC721TransferExempt(exemptAddress, true);
      bool isExempt = numberGoUp.erc721TransferExempt(exemptAddress);
      assertTrue(isExempt, "Address should be exempt");
   }

   function testTransferTokensFromOwner() public {
      // Transfer 5 tokens to user
      numberGoUp.transfer(user, 5 * (10 ** decimals));
      assertEq(numberGoUp.erc20BalanceOf(user), 5 * (10 ** decimals), "User should have 5 whole ERC20 tokens");
      // Check for minted NFTs owned by user
      assertEq(numberGoUp.erc721TotalSupply(), 5, "Total supply should be 5");
      assertEq(numberGoUp.erc721BalanceOf(user), 5, "User should have 5 NFTs");
      assertEq(numberGoUp.ownerOf(1), user, "Token 1 should be owned by user");
      assertEq(numberGoUp.ownerOf(5), user, "Token 5 should be owned by user");
      // Check that ID 1 is the next in the selling queue
      assertEq(numberGoUp.getNextQueueId(user), 1, "Next queue ID should be 1");
      // assertEq(numberGoUp.getERC721TokensInQueue(user, 10), [1]);
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
      numberGoUp.transfer(user, 5 * (10 ** decimals));

      // Test ERC-721 balance requirement
      vm.prank(user);
      vm.expectRevert();
      numberGoUp.stakeNFT(6);  // Trying to stake a non-existent token

      // Test ERC-20 balance requirement
      vm.startPrank(user);
      numberGoUp.transfer(address(1), 5 * (10 ** decimals));  // Transfer all ERC-20 tokens away
      vm.expectRevert();
      numberGoUp.stakeNFT(1);
      vm.stopPrank();
   }

   function testStakeNFTLogic() public {
      // Setup
      numberGoUp.transfer(user, 5 * (10 ** decimals));
      uint256 initialERC20Balance = numberGoUp.erc20BalanceOf(user);
      // uint256 initialERC721Balance = numberGoUp.erc721BalanceOf(user);
      
      console.log("Items in user's selling queue before staking ID 1:");
      uint256 queueSize = numberGoUp.getERC721TokensInQueue(user, 10).length;
      for (uint256 i = 0; i < queueSize; i++) {
          uint256 tokenId = numberGoUp.getIdAtQueueIndex(user, uint128(i));
          console.log(tokenId);
      }
      vm.startPrank(user);
      
      // Stake NFT
      numberGoUp.stakeNFT(1);

      // Check ERC-20 balance reduced
      assertEq(numberGoUp.erc20BalanceOf(user), initialERC20Balance - 1 * (10 ** decimals), "User should have 4 whole ERC20 tokens");
      // Check ERC-20 added to staked bank
      assertEq(numberGoUp.getStakedERC20Balance(user), 1 * (10 ** decimals), "User should have 1 whole ERC20 token staked");

      // Check ID removed from selling queue
      uint256[] memory queuedTokens = numberGoUp.getERC721TokensInQueue(user, 10);
      for (uint i = 0; i < queuedTokens.length; i++) {
         assertFalse(queuedTokens[i] == 1, "Token 1 should not be in the selling queue");
      }

      // Check ID added to staked stack
      uint256[] memory stakedTokens = numberGoUp.getStakedTokens(user);
         assertEq(stakedTokens[0], 1, "Token 1 should be staked");

      // Print out items in the selling queue for user
      console.log("Items in user's selling queue after staking ID 1:");
      queueSize = numberGoUp.getERC721TokensInQueue(user, 10).length;
      for (uint256 i = 0; i < queueSize; i++) {
          uint256 tokenId = numberGoUp.getIdAtQueueIndex(user, uint128(i));
          console.log(tokenId);
      }

      vm.stopPrank();
   }

   function testUnstakeNFTOwnershipRequirement() public {
      // Setup
      numberGoUp.transfer(user, 5 * (10 ** decimals));
      vm.prank(user);
      numberGoUp.stakeNFT(1);

      // Test ownership requirement
      vm.expectRevert();
      numberGoUp.unStakeNFT(1);
   }

   function testUnstakeNFTStakedTokenRequirement() public {
      // Setup
      numberGoUp.transfer(user, 5 * (10 ** decimals));

      // Test unstaking a token that hasn't been staked
      vm.prank(user);
      vm.expectRevert();
      numberGoUp.unStakeNFT(1);
   }

   function testUnstakeNFTLogic() public {
      // Setup
      numberGoUp.transfer(user, 5 * (10 ** decimals));
      vm.startPrank(user);
      numberGoUp.stakeNFT(1);
      uint256 initialERC20Balance = numberGoUp.erc20BalanceOf(user);
      uint256 initialStakedBalance = numberGoUp.getStakedERC20Balance(user);
      uint256 initialQueueLength = numberGoUp.getERC721TokensInQueue(user, 10).length;

      // Unstake NFT
      numberGoUp.unStakeNFT(1);

      // Check ERC-20 retrieved from staked bank
      assertEq(numberGoUp.getStakedERC20Balance(user), initialStakedBalance - 1 * (10 ** decimals), "User should have 0 whole ERC20 tokens staked");

      // Check ERC-20 added to balance
      assertEq(numberGoUp.erc20BalanceOf(user), initialERC20Balance + 1 * (10 ** decimals), "User should have 1 whole ERC20 token");

      // Check ID added back to selling queue
      assertEq(numberGoUp.getERC721TokensInQueue(user, 10).length, initialQueueLength + 1, "Selling queue should have one more token");

      // Check ID removed from staked array
      uint256[] memory stakedTokens = numberGoUp.getStakedTokens(user);
      for (uint i = 0; i < stakedTokens.length; i++) {
         assertFalse(stakedTokens[i] == 1, "Token 1 should not be staked");
      }
      
      // Print out items in the selling queue for user
      console.log("Items in user's selling queue after unstake:");
      uint256 queueSize = numberGoUp.getERC721TokensInQueue(user, 10).length;
      for (uint256 i = 0; i < queueSize; i++) {
          uint256 tokenId = numberGoUp.getIdAtQueueIndex(user, uint128(i));
          console.log(tokenId);
      }
      vm.stopPrank();
   }
   function testStakeNFTWithTwentyNFTs() public {
      // Setup: Transfer 20 whole tokens to user
      uint256 transferAmount = 20 * (10 ** decimals);
      numberGoUp.transfer(user, transferAmount);

      // Verify initial state
      assertEq(numberGoUp.erc721BalanceOf(user), 20, "User should have 20 NFTs initially");
      assertEq(numberGoUp.erc20BalanceOf(user), transferAmount, "User should have 20 whole ERC20 tokens initially");

      // Get initial queue state
      uint256 initialQueueLength = numberGoUp.getQueueLength(user);
      
      // Apply prank and stake one NFT
      vm.startPrank(user);
      uint256 tokenIdToStake = numberGoUp.getIdAtQueueIndex(user, 0);
      numberGoUp.stakeNFT(tokenIdToStake);

      // Verify post-stake state
      assertEq(numberGoUp.erc721BalanceOf(user), 20, "User should have 20 NFTs after staking");
      assertEq(numberGoUp.erc20BalanceOf(user), transferAmount - (1 * (10 ** decimals)), "User should have 19 whole ERC20 tokens after staking");
      assertEq(numberGoUp.getStakedERC20Balance(user), 1 * (10 ** decimals), "User should have 1 whole ERC20 token staked");

      // Verify queue state
      assertEq(numberGoUp.getQueueLength(user), initialQueueLength - 1, "Selling queue should have one less token");

      // Verify staked token
      uint256[] memory stakedTokens = numberGoUp.getStakedTokens(user);
      assertEq(stakedTokens.length, 1, "User should have 1 staked token");
      assertEq(stakedTokens[0], tokenIdToStake, "Staked token ID should match");

      // Verify token is no longer in selling queue
      uint256[] memory queueTokens = numberGoUp.getERC721TokensInQueue(user, 19);
      for (uint i = 0; i < queueTokens.length; i++) {
          assertFalse(queueTokens[i] == tokenIdToStake, "Staked token should not be in selling queue");
      }
   }

   function testTransferTokensBetweenNonOwnerAddresses() public {
      // Initial setup
      uint256 initialOwnerBalance = numberGoUp.erc20BalanceOf(owner);
      uint256 transferAmount = 5 * (10 ** decimals);
      vm.prank(owner);
      // Transfer from owner to user
      numberGoUp.transfer(user, transferAmount);
      assertEq(numberGoUp.erc20BalanceOf(owner), initialOwnerBalance - transferAmount, "Owner should have 4 whole ERC20 tokens");
      assertEq(numberGoUp.erc20BalanceOf(user), transferAmount, "User should have 1 whole ERC20 token");

      // Transfer from user to user2
      uint256 secondTransferAmount = 2 * (10 ** decimals);
      vm.prank(user);
      numberGoUp.transfer(user2, secondTransferAmount);

      // Check ERC20 balances
      assertEq(numberGoUp.erc20BalanceOf(user), transferAmount - secondTransferAmount, "User should have 3 whole ERC20 tokens");
      assertEq(numberGoUp.erc20BalanceOf(user2), secondTransferAmount, "User2 should have 2 whole ERC20 tokens");

      // Check ERC721 balances
      assertEq(numberGoUp.erc721BalanceOf(user), 3, "User should have 3 NFTs");
      assertEq(numberGoUp.erc721BalanceOf(user2), 2, "User2 should have 2 NFTs");

      // Check total supply remains constant
      assertEq(numberGoUp.totalSupply(), initialOwnerBalance);

      // Check specific token ownership
      assertEq(numberGoUp.ownerOf(3), user, "Token 3 should be owned by user");
      assertEq(numberGoUp.ownerOf(4), user, "Token 4 should be owned by user");
      assertEq(numberGoUp.ownerOf(5), user, "Token 5 should be owned by user");
      // The tests below are failing. 
      assertEq(numberGoUp.ownerOf(1), user2, "Token 1 should be owned by user2");
      assertEq(numberGoUp.ownerOf(2), user2, "Token 2 should be owned by user2");

      uint256 user2NFTs = numberGoUp.erc721BalanceOf(user2);
      console.log("Number of NFTs owned by User2: ", user2NFTs);

      uint256[] memory user2NFTArray = numberGoUp.owned(user2);
      console.log("NFT IDs owned by User2:");
      for (uint i = 0; i < user2NFTArray.length; i++) {
         console.log(user2NFTArray[i]);
      }

      uint256[] memory user1NFTArray = numberGoUp.owned(user);
      console.log("NFT IDs owned by User: ");
      for (uint i = 0; i < user1NFTArray.length; i++) {
         console.log(user1NFTArray[i]);
      }

       // Print out items in the selling queue for user
      console.log("Items in user's selling queue:");
      uint256 queueSize = numberGoUp.getERC721TokensInQueue(user, 10).length;
      for (uint256 i = 0; i < queueSize; i++) {
          uint256 tokenId = numberGoUp.getIdAtQueueIndex(user, uint128(i));
          console.log(tokenId);
      }
      // Print out items in the selling queue for user2
      console.log("Items in user2's selling queue:");
       queueSize = numberGoUp.getERC721TokensInQueue(user2, 10).length;
      for (uint256 i = 0; i < queueSize; i++) {
          uint256 tokenId = numberGoUp.getIdAtQueueIndex(user2, uint128(i));
          console.log(tokenId);
      }



      // Try to transfer more than balance
      vm.expectRevert("Insufficient balance");
      numberGoUp.transfer(user2, 4 * (10 ** decimals));

      // Check balances remain unchanged after failed transfer
      assertEq(numberGoUp.erc20BalanceOf(user), 3 * (10 ** decimals), "User should have 3 whole ERC20 tokens");
      assertEq(numberGoUp.erc20BalanceOf(user2), 2 * (10 ** decimals), "User2 should have 2 whole ERC20 tokens");
   }
}
