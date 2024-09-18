// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {INGU404} from "./interfaces/INGU404.sol";
import {ERC721Events} from "./lib/ERC721Events.sol";
import {ERC20Events} from "./lib/ERC20Events.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";

import "./lib/DoubleEndedQueue.sol";

abstract contract NGU404 is INGU404 {
    using DoubleEndedQueue for DoubleEndedQueue.Uint256Deque;

    /// @dev The name of the token.
    string public name;

    /// @dev The symbol for the token.
    string public symbol;

    /// @dev The number of decimals for the ERC20 token.
    uint8 public immutable decimals;

    /// @dev Number of units for the ERC20 token.
    uint256 public immutable units;

    /// @dev The total supply of ERC20 tokens.
    uint256 public totalSupply;

    /// @dev The total number of ERC721 tokens minted.
    uint256 public minted;

  /// @dev Initial chain id for EIP-2612 support
  uint256 internal immutable _INITIAL_CHAIN_ID;

  /// @dev Initial domain separator for EIP-2612 support
  bytes32 internal immutable _INITIAL_DOMAIN_SEPARATOR;

    /// @dev A mapping of users to their held ERC20 tokens.
    mapping(address => uint256) public stakedERC20TokenBank;

    /// @dev ERC20 user balances.
    mapping(address => uint256) public balanceOf;

    /// @dev ERC20 allowances, from grantor to grantee.
    mapping(address => mapping(address => uint256)) public allowance;

    /// @dev Addresses that are exempt from ERC-721 transfer, typically for gas savings (pairs, routers, etc)
    mapping(address => bool) internal _erc721TransferExempt;

    /// @dev EIP-2612 nonces
    mapping(address => uint256) public nonces;

   /// @notice - Queue of NFTs which are unstaked, and for sale. Staked NFTs are not included. 
   mapping(address => DoubleEndedQueue.Uint256Deque) private _sellingQueue;

   /// @notice - The next two mappings are for tracking who owns a token and the index in their queue.
   ///@dev owner => [owned token IDs]
   mapping(address => uint256[]) private _owned;
   /// @dev token ID => owner+index
   mapping(uint256 => uint256) private _ownedData;

   /// @dev Address bitmask for packed ownership data
   uint256 private constant _BITMASK_ADDRESS = (1 << 160) - 1;
   /// @dev Owned index bitmask for packed ownership data
   uint256 private constant _BITMASK_OWNED_INDEX = ((1 << 96) - 1) << 160;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) {
        name = name_;
        symbol = symbol_;

        if (decimals < 18) {
            revert DecimalsTooLow();
        }
        decimals = decimals_;
        units = 10 ** decimals;

   // EIP-2612 initialization
    _INITIAL_CHAIN_ID = block.chainid;
    _INITIAL_DOMAIN_SEPARATOR = _computeDomainSeparator();
    }

/// @notice tokenURI must be implemented by child contract
   function tokenURI(uint256 id_) public view virtual returns (string memory);

/// @notice This function handles consolidated ERC721 functions. 
/// Handles both minting and transferring 721s, based on from_ and to_ addresses.
  function _transferERC721(
    address from_,
    address to_,
    uint256 id_
) internal virtual {

   uint256 tokenId;
   if (from_ != address(0)) {
   // If this sale is coming from an address.  
      // Pop from the sender's selling queue
      tokenId = _sellingQueue[from_].popFront();
      // Remove from from_'s _owned array.
      removeOwnedById(from_, tokenId);
   } else {
      tokenId = id_;
   }
   
   // If it's not a burn
    if (to_ != address(0)) {
      // Add the token ID to the to_'s _owned array
      addOwnedToken(to_, tokenId);
      // Sets the owner of the token ID to the to_ address in _ownedData. 
      _setOwnerOf(tokenId, to_);
      // Sets the owned index of the token ID to the length of the to_'s _owned array.
      _setOwnedIndex(tokenId, _owned[to_].length - 1);
      // Add the token ID to the to_'s selling queue
      _sellingQueue[to_].pushBack(tokenId);
    } else {
   // If this is a burn
      // Front of queue already popped in the _withdrawAndBurn721 function. 
      // Set owner to 0x0 in the ownedData mapping. 
      _setOwnerOf(tokenId, address(0));
      // delete the token from the ownedData mapping.
      delete _ownedData[tokenId];
    }

    emit ERC721Events.Transfer(from_, to_, tokenId);
}

  /// @notice This is the lowest level ERC-20 transfer function, which
  /// should be used for both normal ERC-20 transfers as well as minting.
  /// Note that this function allows transfers to and from 0x0.
  function _transferERC20(
    address from_,
    address to_,
    uint256 value_
  ) internal virtual {
    // Minting is a special case for which we should not check the balance of
    // the sender, and we should increase the total supply.
    if (from_ == address(0)) {
      totalSupply += value_;
    } else {
      // Deduct value from sender's balance.
      balanceOf[from_] -= value_;
    }

    // Update the recipient's balance.
    // Can be unchecked because on mint, adding to totalSupply is checked, and on transfer balance deduction is checked.
    unchecked {
      balanceOf[to_] += value_;
    }

    emit ERC20Events.Transfer(from_, to_, value_);
  }
function ownerOf(uint256 tokenId) public view returns (address) {
   address owner = _getOwnerOf(tokenId);
   require(owner != address(0), "NGU404: owner query for nonexistent token");
   return owner;
}

function owned(
   address owner_
) public view virtual returns (uint256[] memory) {
   return _owned[owner_];
}

function erc721BalanceOf(
   address owner_
) public view virtual returns (uint256) {
   return balanceOf[owner_];
}

function erc20BalanceOf(
   address owner_
) public view virtual returns (uint256) {
   return balanceOf[owner_];
}

function erc20Staked(
   address owner_
) public view virtual returns (uint256) {
   return stakedERC20TokenBank[owner_];
}

function erc20TotalSupply() public view virtual returns (uint256) {
   return totalSupply;
}

function erc721TotalSupply() public view virtual returns (uint256) {
   return minted;
}

function getNextQueueId(
   address owner_
) public view virtual returns (uint256) {
   return _sellingQueue[owner_].front();
}

/// @notice - This is the function we will use to get N items from the queue. Iterate over this for indices 0 to n - 1.
function getIdAtQueueIndex(
   address owner_,
   uint128 index_
) public view virtual returns (uint256) {
   return _sellingQueue[owner_].at(index_);
}

/// @notice - This does what is intended above but it's mostly in the smart contract. Secondary implementation option. 
function getERC721TokensInQueue(
    uint256 start_,
    address owner_,
    uint256 count_
  ) public view virtual returns (uint256[] memory) {
    uint256[] memory tokensInQueue = new uint256[](count_);

    for (uint256 i = start_; i < start_ + count_; ) {
      tokensInQueue[i - start_] = _sellingQueue[owner_].at(i);

      unchecked {
        ++i;
      }
    }

    return tokensInQueue;
  }

// Helper function to add a token ID to an owner's _owned array
function addOwnedToken(address owner, uint256 tokenId) internal {
    uint256 index = _owned[owner].length;
    _owned[owner].push(tokenId);

    // Update packed data
    _setOwnerOf(tokenId, owner);
    _setOwnedIndex(tokenId, index);
}

   function stakeNFT(
      uint256 id_
   ) internal virtual returns (bool) {
      address staker = msg.sender;
      // 1. Remove one whole ERC20 token from the staker's balanceOf mapping
      require(balanceOf[staker] >= units, "Insufficent balance to stake");
      balanceOf[staker] -= units;

      // 2. Add one whole ERC20 token to the staker's stakedERC20TokenBank mapping
      stakedERC20TokenBank[staker] += units;

      //3. Remove the associated ERC721 token ID from the _selling queue
      _sellingQueue[msg.sender].removeById(id_);

      return true;
   }

   function unStakeNFT(
      uint256 id_
   ) internal virtual returns (bool) {
      address staker = msg.sender;

      // 1. Remove one whole ERC20 token from the staker's stakedERC20TokenBank mapping
      require(stakedERC20TokenBank[staker] >= units, "Insufficent balance to unstake");
      stakedERC20TokenBank[staker] -= units;

      // 2. Add one whole ERC20 token to the staker's balanceOf mapping
      balanceOf[staker] += units;

      // 3. Add the associated ERC72 token ID back to the _sellingQueue
      _sellingQueue[staker].pushBack(id_);

      return true;
   }

/// @notice - Approvals for ERC20 balance management.
/// in the previous version of ERC404, this function was used for 721 and 20 approvals.
/// we don't delegte 721 approvals in this contract. 
   function approve(
      address spender_,
      uint256 value_
   ) public virtual returns (bool) {
      if (spender_ == address(0)) {
         revert InvalidSpender();
      }

      allowance[msg.sender][spender_] = value_;

      emit ERC20Events.Approval(msg.sender, spender_, value_);

      return true;
   }

function transferFrom(
   address from_,
   address to_,
   uint256 value_
) public virtual returns (bool) {
   if (from_ == address(0) ){
      revert InvalidSender();
   }

   if (to_ == address(0)) {
      revert InvalidRecipient();
   }

   uint256 allowed = allowance[from_][msg.sender];

   // Check if operator has sufficent balance
   if (allowed != type(uint256).max) {
      allowance[from_][msg.sender] = allowed - value_;
   }

   return _transferERC20WithERC721(from_, to_, value_);
}


/// @notice - This is mostly taken from the Pandora Labs ERC404 contract, with some modifications for the queues. 
function _transferERC20WithERC721(
   address from_,
   address to_,
   uint256 value_
) internal virtual returns (bool) {
   uint256 erc20BalanceOfSenderBefore = erc20BalanceOf(from_);
   uint256 erc20BalanceOfRecipientBefore = erc20BalanceOf(to_);

   _transferERC20(from_, to_, value_);

   bool isFromERC721TransferExempt = erc721TransferExempt(from_);
   bool isToERC721TransferExempt = erc721TransferExempt(to_);

   if (isFromERC721TransferExempt && isToERC721TransferExempt) {
      // Case 1 - Both Sender and Recipient are ERC721 Transfer Exempt
      // DO NOTHING
   } else if (isFromERC721TransferExempt) {
      // Case 2 - Sender is ERC721 Exempt, but recipient is not.
      uint256 tokensToMint = (balanceOf[to_]/units) - (erc20BalanceOfRecipientBefore / units);

      for (uint256 i = 0; i < tokensToMint; ) {
         _mintERC721(to_);
         unchecked {
            ++i;
         }
      }
   } else if (isToERC721TransferExempt) {
      // Case 3 - Recipient is ERC721 exempt. Burn the ERC721 tokens. 
      // only cares about whole number increments.
      uint256 tokensToBurn = (erc20BalanceOfSenderBefore / units) - (balanceOf[from_] / units);

      for (uint256 i = 0; i < tokensToBurn;) {
         _withdrawAndBurnERC721(from_);
         unchecked {
            ++i;
         }
   }
   } else {
      // Case 4 - Neither the sender nor the recipient are ERC-721 transfer exempt.
      // Strategy:
      // 1. First deal with the whole tokens. These are easy and will just be transferred.
      // 2. Look at the fractional part of the value:
      //   a) If it causes the sender to lose a whole token that was represented by an NFT due to a
      //      fractional part being transferred, withdraw and store an additional NFT from the sender.
      //   b) If it causes the receiver to gain a whole new token that should be represented by an NFT
      //      due to receiving a fractional part that completes a whole token, retrieve or mint an NFT to the recevier.

      // Whole tokens worth of ERC-20s get transferred as ERC-721s without any burning/minting.
      uint256 nftsToTransfer = value_/units;
      for (uint256 i = 0; i < nftsToTransfer; ){
         uint256 tokenId = _sellingQueue[from_].popFront();
         _transferERC721(from_, to_, tokenId);
         unchecked {
            ++i;
         }
      }
      // If the transfer changes either the sender or the recipient's holdings from a fractional to a non-fractional
      // amount (or vice versa), adjust ERC-721s.

      // First check if the send causes the sender to lose a whole token that was represented by an ERC-721
      // due to a fractional part being transferred.
      //
      // Process:
      // Take the difference between the whole number of tokens before and after the transfer for the sender.
      // If that difference is greater than the number of ERC-721s transferred (whole units), then there was
      // an additional ERC-721 lost due to the fractional portion of the transfer.
      // If this is a self-send and the before and after balances are equal (not always the case but often),
      // then no ERC-721s will be lost here.
      if (
         erc20BalanceOfSenderBefore / units - erc20BalanceOf(from_) / units > nftsToTransfer
      ) {
         _withdrawAndBurnERC721(from_);
      }

       // Then, check if the transfer causes the receiver to gain a whole new token which requires gaining
      // an additional ERC-721.
      //
      // Process:
      // Take the difference between the whole number of tokens before and after the transfer for the recipient.
      // If that difference is greater than the number of ERC-721s transferred (whole units), then there was
      // an additional ERC-721 gained due to the fractional portion of the transfer.
      // Again, for self-sends where the before and after balances are equal, no ERC-721s will be gained here.

      if (
         erc20BalanceOf(to_) / units - erc20BalanceOfRecipientBefore / units > nftsToTransfer
      ) {
         _mintERC721(to_);
      }
   }

   return true;
}

function _withdrawAndBurnERC721(
   address from_
) internal virtual {
   if (from_ == address(0)) {
      revert InvalidSender();
   }

   // Get the first token in the owner's queue
   uint256 tokenId = _sellingQueue[from_].popFront();

   _transferERC721(from_, address(0), tokenId);

}

  /// @notice Internal function for ERC20 minting
  /// @dev This function will allow minting of new ERC20s.
  ///      If mintCorrespondingERC721s_ is true, and the recipient is not ERC-721 exempt, it will
  ///      also mint the corresponding ERC721s.
  /// Handles ERC-721 exemptions.
  function _mintERC20(address to_, uint256 value_) internal virtual {
    /// You cannot mint to the zero address (you can't mint and immediately burn in the same transfer).
    if (to_ == address(0)) {
      revert InvalidRecipient();
    }

    if (totalSupply + value_ > type(uint256).max) {
      revert MintLimitReached();
    }

    _transferERC20WithERC721(address(0), to_, value_);
  }

   /// @notice Internal function for ERC-721 minting and retrieval from the bank.
  /// @dev This function will allow minting of new ERC-721s up to the total fractional supply. It will
  ///      first try to pull from the bank, and if the bank is empty, it will mint a new token.
  /// Does not handle ERC-721 exemptions.
  function _mintERC721(address to_) internal virtual {
    if (to_ == address(0)) {
      revert InvalidRecipient();
    }

    uint256 id;

   // Increase minted counter
   ++minted;

   // Reserve max uint256 for approvals
   if (minted == type(uint256).max) {
      revert MintLimitReached();
   }

   id = minted;

   address erc721Owner = _getOwnerOf(id);

    // The token should not already belong to anyone besides 0x0 or this contract.
    // If it does, something is wrong, as this should never happen.
    if (erc721Owner != address(0)) {
      revert AlreadyExists();
    }

    // Transfer the token to the recipient, either transferring from the contract's bank or minting.
    // Does not handle ERC-721 exemptions.
    _transferERC721(erc721Owner, to_, id);
  }


  function erc721TransferExempt(
    address target_
  ) public view virtual returns (bool) {
    return target_ == address(0) || _erc721TransferExempt[target_];
  }

    /// @notice Function for self-exemption
  function setSelfERC721TransferExempt(bool state_) public virtual {
    _setERC721TransferExempt(msg.sender, state_);
  }

    /// @notice Initialization function to set pairs / etc, saving gas by avoiding mint / burn on unnecessary targets
  function _setERC721TransferExempt(
    address target_,
    bool state_
  ) internal virtual {
    if (target_ == address(0)) {
      revert InvalidExemption();
    }
    _erc721TransferExempt[target_] = state_;
  }

/// @notice _setOwnerOf, _getOwnerOf, _getOwnedIndex, and _setOwnedIndex are helper functions for managing the packed data in _ownedData.
   function _setOwnerOf(uint256 tokenId, address owner) internal virtual {
      uint256 data = _ownedData[tokenId];

      assembly {
         data:= add (
            and(data, _BITMASK_OWNED_INDEX),
            and(owner, _BITMASK_ADDRESS)
         )
      }
      _ownedData[tokenId] = data;
   }

   function _getOwnerOf(uint256 tokenId) internal view virtual returns (address owner_) {
      uint256 data = _ownedData[tokenId];

      assembly {
         owner_ := and(data, _BITMASK_ADDRESS)
      }
   }

   function _getOwnedIndex(uint256 tokenId) internal view virtual returns (uint256 ownedIndex_) {
      uint256 data = _ownedData[tokenId];

      assembly {
         ownedIndex_ := shr(160, data)
      }
   }

   function _setOwnedIndex(uint256 id_, uint256 index_) internal virtual {
    uint256 data = _ownedData[id_];

    if (index_ > _BITMASK_OWNED_INDEX >> 160) {
      revert OwnedIndexOverflow();
    }

    assembly {
      data := add(
        and(data, _BITMASK_ADDRESS),
        and(shl(160, index_), _BITMASK_OWNED_INDEX)
      )
    }

    _ownedData[id_] = data;
  }


/// @notice - removeOnwedById is a helper function to remove the token ID from the owner's _owned array.
function removeOwnedById(address owner, uint256 tokenId) internal {
    uint256 index = _getOwnedIndex(tokenId);
    uint256 lastIndex = _owned[owner].length - 1;

    if (index != lastIndex) {
        uint256 lastTokenId = _owned[owner][lastIndex];

        // Swap the token IDs
        _owned[owner][index] = lastTokenId;

        // Update the owned index in the packed data for the swapped token
        _setOwnedIndex(lastTokenId, index);
    }

    // Remove the last element
    _owned[owner].pop();
}

 /// @notice Function for EIP-2612 permits (ERC-20 only).
  /// @dev Providing type(uint256).max for permit value results in an
  ///      unlimited approval that is not deducted from on transfers.
  function permit(
    address owner_,
    address spender_,
    uint256 value_,
    uint256 deadline_,
    uint8 v_,
    bytes32 r_,
    bytes32 s_
  ) public virtual {
    if (deadline_ < block.timestamp) {
      revert PermitDeadlineExpired();
    }

    // permit cannot be used for ERC-721 token approvals, so ensure
    // the value does not fall within the valid range of ERC-721 token ids.
    if (value_ >= type(uint256).max) {
      revert InvalidApproval();
    }

    if (spender_ == address(0)) {
      revert InvalidSpender();
    }

    unchecked {
      address recoveredAddress = ecrecover(
        keccak256(
          abi.encodePacked(
            "\x19\x01",
            DOMAIN_SEPARATOR(),
            keccak256(
              abi.encode(
                keccak256(
                  "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                ),
                owner_,
                spender_,
                value_,
                nonces[owner_]++,
                deadline_
              )
            )
          )
        ),
        v_,
        r_,
        s_
      );

      if (recoveredAddress == address(0) || recoveredAddress != owner_) {
        revert InvalidSigner();
      }

      allowance[recoveredAddress][spender_] = value_;
    }

    emit ERC20Events.Approval(owner_, spender_, value_);
  }

  /// @notice Internal function to compute domain separator for EIP-2612 permits
  function _computeDomainSeparator() internal view virtual returns (bytes32) {
    return
      keccak256(
        abi.encode(
          keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
          ),
          keccak256(bytes(name)),
          keccak256("1"),
          block.chainid,
          address(this)
        )
      );
  }
  /// @notice Returns domain initial domain separator, or recomputes if chain id is not equal to initial chain id
  function DOMAIN_SEPARATOR() public view virtual returns (bytes32) {
    return
      block.chainid == _INITIAL_CHAIN_ID
        ? _INITIAL_DOMAIN_SEPARATOR
        : _computeDomainSeparator();
  }

  function supportsInterface(
    bytes4 interfaceId
  ) public view virtual returns (bool) {
    return
      interfaceId == type(INGU404).interfaceId ||
      interfaceId == type(IERC165).interfaceId;
  }


}
