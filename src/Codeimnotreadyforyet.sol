   /// @dev Internal function for the transfering and minting of ERC20 tokens.
    /// lowest level which should be used for normal 20 transfers as well as minting.
    function _transferERC20(
        address from_,
        address to_,
        uint256 value_
    ) internal virtual {
        // Condition for mingting tokens (transfer from 0x0)
        // increase the total supply
        if (from_ == address(0)) {
            totalSupply += value_;
        } else {
            balanceOf[from_] -= value_;
        }

        // Update recipient's balance
        // Can be unchecked because on mint, adding to totalSupply is checked, and on transfer balance deduction is checked.
        // TODO: Evaluate the above statement
        unchecked {
            balanceOf[to_] += value_;
        }

        emit ERC20Events.Transfer(from_, to_, value_);
    }

    /// @notice internal function for transfering ERC721 tokens.
    /// @dev Assign the token to a new owner and remove from the old owner.
    /// Allows transfers to and from 0x0
    function _transferERC721(
        address from_,
        address to_,
        uint256 id_
    ) internal virtual {
        // If this is not a mint, handle record keeping for transfer from previous owner.
        if (from_ != address(0)) {
            // Reset previous approvals (not sure if this is necessary since I don't have 721 approvals)
            // delete getApproved[id_];
            uint256 updatedId = _owned[from_][0];

            if (updatedId != id_) {
                uint256 updatedIndex = _getOwnedIndex(id_);

                //update _owned for sender
                _owned[from_][updatedIndex] = updatedId;
                // update index for the moved id
                _setOwnedIndex(updatedId, updatedIndex);
            }

            // Pop the last element of the array
            for (uint256 i = 0; i < _owned[from_].length - 1; i++) {
                _owned[from_][i] = _owned[from_][i + 1];
            }

            _owned[from_].pop();
        }
    }

    /// @notice Utility function for getting the owner of a specific 721 token ID.
    function _getOwnerOf721(
        uint256 id_
    ) internal view virtual returns (address ownerOf_) {
        uint256 data = _ownedData[id_];

        assembly {
            ownerOf_ := and(data, _BITMASK_ADDRESS)
        }
    }

    /// @notice Internal function for ERC-20 transfers. Also handles any ERC-721 transfers that may be required.
    // Handles ERC-721 exemptions.
    function _transferERC20WithERC721(
        address from_,
        address to_,
        uint256 value_
    ) internal virtual returns (bool) {
        uint256 erc20BalanceOfSenderBefore = erc20BalanceOf(from_);
        uint256 erc20BalanceOfReceiverBefore = erc20BalanceOf(to_);

        _transferERC20(from_, to_, value_);

        // Preload for gas savings on branches
        bool isFromERC721TransferExempt = erc721TransferExempt(from_);
        bool isToERC721TransferExempt = erc721TransferExempt(to_);

        // Skip _withdrawAndStoreERC721 and/or _retrieveOrMintERC721 for ERC-721 transfer exempt addresses
        // 1) to save gas
        // 2) because ERC-721 transfer exempt addresses won't always have/need ERC-721s corresponding to their ERC20s.
        if (isFromERC721TransferExempt && isToERC721TransferExempt) {
            // Case 1) Both sender and recipient are ERC-721 transfer exempt. No ERC-721s need to be transferred.
            // NOOP.
        } else if (isFromERC721TransferExempt) {
            // Case 2) The sender is ERC-721 transfer exempt, but the recipient is not. Contract should not attempt
            //         to transfer ERC-721s from the sender, but the recipient should receive ERC-721s
            //         from the bank/minted for any whole number increase in their balance.
            // Only cares about whole number increments.
            uint256 tokensToRetrieveOrMint = (balanceOf[to_] / units) -
                (erc20BalanceOfReceiverBefore / units);
            for (uint256 i = 0; i < tokensToRetrieveOrMint; ) {
                _retrieveOrMintERC721(to_);
                unchecked {
                    ++i;
                }
            }
        } else if (isToERC721TransferExempt) {
            // Case 3) The sender is not ERC-721 transfer exempt, but the recipient is. Contract should attempt
            //         to withdraw and store ERC-721s from the sender, but the recipient should not
            //         receive ERC-721s from the bank/minted.
            // Only cares about whole number increments.
            uint256 tokensToWithdrawAndStore = (erc20BalanceOfSenderBefore /
                units) - (balanceOf[from_] / units);
            for (uint256 i = 0; i < tokensToWithdrawAndStore; ) {
                _withdrawAndStoreERC721(from_);
                unchecked {
                    ++i;
                }
            }
        } else {
            // Case 4) Neither the sender nor the recipient are ERC-721 transfer exempt.
            // Strategy:
            // 1. First deal with the whole tokens. These are easy and will just be transferred.
            // 2. Look at the fractional part of the value:
            //   a) If it causes the sender to lose a whole token that was represented by an NFT due to a
            //      fractional part being transferred, withdraw and store an additional NFT from the sender.
            //   b) If it causes the receiver to gain a whole new token that should be represented by an NFT
            //      due to receiving a fractional part that completes a whole token, retrieve or mint an NFT to the recevier.

            // Whole tokens worth of ERC-20s get transferred as ERC-721s without any burning/minting.
            uint256 nftsToTransfer = value_ / units;
            for (uint256 i = 0; i < nftsToTransfer; ) {
                // Pop from sender's ERC-721 stack and transfer them (LIFO)
                uint256 indexOfLastToken = _owned[from_].length - 1;
                uint256 tokenId = _owned[from_][indexOfLastToken];
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
                erc20BalanceOfSenderBefore /
                    units -
                    erc20BalanceOf(from_) /
                    units >
                nftsToTransfer
            ) {
                _withdrawAndStoreERC721(from_);
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
                erc20BalanceOf(to_) /
                    units -
                    erc20BalanceOfReceiverBefore /
                    units >
                nftsToTransfer
            ) {
                _retrieveOrMintERC721(to_);
            }
        }

        return true;
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

        if (totalSupply + value_ > ID_ENCODING_PREFIX) {
            revert MintLimitReached();
        }

        _transferERC20WithERC721(address(0), to_, value_);
    }

    /// @notice Internal function for ERC-721 minting and retrieval from the bank.
    /// @dev This function will allow minting of new ERC-721s up to the total fractional supply. It will
    ///      first try to pull from the bank, and if the bank is empty, it will mint a new token.
    /// Does not handle ERC-721 exemptions.
    function _retrieveOrMintERC721(address to_) internal virtual {
        if (to_ == address(0)) {
            revert InvalidRecipient();
        }

        uint256 id;

        if (!_storedERC721Ids.empty()) {
            // If there are any tokens in the bank, use those first.
            // Pop off the end of the queue (FIFO).
            id = _storedERC721Ids.popBack();
        } else {
            // Otherwise, mint a new token, should not be able to go over the total fractional supply.
            ++minted;

            // Reserve max uint256 for approvals
            if (minted == type(uint256).max) {
                revert MintLimitReached();
            }

            id = ID_ENCODING_PREFIX + minted;
        }

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

    /// @notice Internal function for ERC-721 deposits to bank (this contract).
    /// @dev This function will allow depositing of ERC-721s to the bank, which can be retrieved by future minters.
    // Does not handle ERC-721 exemptions.
    function _withdrawAndStoreERC721(address from_) internal virtual {
        if (from_ == address(0)) {
            revert InvalidSender();
        }

        // Retrieve the latest token added to the owner's stack (LIFO).
        uint256 id = _owned[from_][_owned[from_].length - 1];

        // Transfer to 0x0.
        // Does not handle ERC-721 exemptions.
        _transferERC721(from_, address(0), id);

        // Record the token in the contract's bank queue.
        _storedERC721Ids.pushFront(id);
    }