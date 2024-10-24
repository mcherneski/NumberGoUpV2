//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {Test} from 'forge-std/Test.sol';
import {console} from "forge-std/console.sol";
import "../src/NumberGoUp.sol";


contract NumberGoUpTest is Test {
   NumberGoUp public numberGoUp;

   address public owner = address(1);
   address public user1 = address(2);
   address public user2 = address(3);
   address public exemptAddress = address(4);
   address public nonExemptAddress = address(5);

   uint8 public decimals = 18;
   uint256 public maxTotalSupplyERC20 = 100000; // 100,000 tokens

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

   function testInitialState() public {
      assertEq(numberGoUp.name(), "NumberGoUp");
      assertEq(numberGoUp.symbol(), "NGU");
      assertEq(numberGoUp.decimals(), 18);
      assertEq(numberGoUp.erc20TotalSupply(), maxTotalSupplyERC20 * (10 ** decimals));
      assertEq(numberGoUp.erc721TotalSupply(), 0);
      assertEq(numberGoUp.erc20BalanceOf(owner), maxTotalSupplyERC20 * (10 ** decimals));
   }

   function testTransferToNonExemptAddress() public {
      uint256 transferAmount = 5 * (10 ** decimals);
      vm.prank(owner);
      numberGoUp.transfer(nonExemptAddress, transferAmount);

      assertEq(numberGoUp.erc20BalanceOf(nonExemptAddress), transferAmount);
      assertEq(numberGoUp.erc721BalanceOf(nonExemptAddress), 5);
      assertEq(numberGoUp.erc721TotalSupply(), 5);
   }

   function testTransferBetweenNonExemptAddresses() public {
      uint256 initialTransfer = 10 * (10 ** decimals);
      uint256 secondaryTransfer = 3 * (10 ** decimals);

      vm.prank(owner);
      numberGoUp.transfer(user1, initialTransfer);

      vm.prank(user1);
      numberGoUp.transfer(user2, secondaryTransfer);

      assertEq(numberGoUp.erc20BalanceOf(user1), 7 * (10 ** decimals));
      assertEq(numberGoUp.erc721BalanceOf(user1), 7);
      assertEq(numberGoUp.erc20BalanceOf(user2), 3 * (10 ** decimals));
      assertEq(numberGoUp.erc721BalanceOf(user2), 3);
   }

   function testStakingAndUnstaking() public {
      uint256 transferAmount = 5 * (10 ** decimals);
      vm.prank(owner);
      numberGoUp.transfer(user1, transferAmount);

      vm.startPrank(user1);
      uint256 tokenIdToStake = numberGoUp.getIdAtQueueIndex(user1, 0);
      numberGoUp.stakeNFT(tokenIdToStake);

      assertEq(numberGoUp.erc20BalanceOf(user1), 4 * (10 ** decimals));
      assertEq(numberGoUp.getStakedERC20Balance(user1), 1 * (10 ** decimals));
      assertEq(numberGoUp.erc721BalanceOf(user1), 5); // ERC721 balance doesn't change on staking

      numberGoUp.unStakeNFT(tokenIdToStake);

      assertEq(numberGoUp.erc20BalanceOf(user1), 5 * (10 ** decimals));
      assertEq(numberGoUp.getStakedERC20Balance(user1), 0);
      assertEq(numberGoUp.erc721BalanceOf(user1), 5);

      vm.stopPrank();
   }

   function testTransferWithFractionalAmount() public {
      uint256 transferAmount = 55 * (10 ** (decimals - 1)); // 5.5 tokens
      vm.prank(owner);
      numberGoUp.transfer(user1, transferAmount);

      assertEq(numberGoUp.erc20BalanceOf(user1), transferAmount);
      assertEq(numberGoUp.erc721BalanceOf(user1), 5);

      vm.prank(user1);
      numberGoUp.transfer(user2, 27 * (10 ** (decimals - 1))); // 2.7 tokens

      assertEq(numberGoUp.erc20BalanceOf(user1), 28 * (10 ** (decimals - 1))); // 2.8 tokens
      assertEq(numberGoUp.erc721BalanceOf(user1), 2);
      assertEq(numberGoUp.erc20BalanceOf(user2), 27 * (10 ** (decimals - 1))); // 2.7 tokens
      assertEq(numberGoUp.erc721BalanceOf(user2), 2);
   }

   function testExemptAddressTransfer() public {
      uint256 transferAmount = 10 * (10 ** decimals);
      vm.prank(owner);
      numberGoUp.transfer(exemptAddress, transferAmount);

      assertEq(numberGoUp.erc20BalanceOf(exemptAddress), transferAmount);
      assertEq(numberGoUp.erc721BalanceOf(exemptAddress), 0);

      vm.prank(exemptAddress);
      numberGoUp.transfer(nonExemptAddress, 5 * (10 ** decimals));

      assertEq(numberGoUp.erc20BalanceOf(exemptAddress), 5 * (10 ** decimals));
      assertEq(numberGoUp.erc721BalanceOf(exemptAddress), 0);
      assertEq(numberGoUp.erc20BalanceOf(nonExemptAddress), 5 * (10 ** decimals));
      assertEq(numberGoUp.erc721BalanceOf(nonExemptAddress), 5);
   }

   function testTokenURI() public {
      vm.prank(owner);
      numberGoUp.transfer(user1, 1 * (10 ** decimals));

      uint256 tokenId = numberGoUp.getIdAtQueueIndex(user1, 0);
      string memory uri = numberGoUp.tokenURI(tokenId);
      assertTrue(bytes(uri).length > 0, "Token URI should not be empty");
   }

   function testFailTransferMoreThanBalance() public {
      vm.prank(owner);
      numberGoUp.transfer(user1, 10 * (10 ** decimals));

      vm.prank(user1);
      numberGoUp.transfer(user2, 11 * (10 ** decimals)); // This should fail
   }

   function testQueueOperations() public {
      vm.prank(owner);
      numberGoUp.transfer(user1, 5 * (10 ** decimals));

      assertEq(numberGoUp.getQueueLength(user1), 5);
      assertEq(numberGoUp.getNextQueueId(user1), 1);

      uint256[] memory queueTokens = numberGoUp.getERC721TokensInQueue(user1, 10);
      assertEq(queueTokens.length, 5);

      vm.prank(user1);
      numberGoUp.stakeNFT(1);

      assertEq(numberGoUp.getQueueLength(user1), 4);
   }
}
