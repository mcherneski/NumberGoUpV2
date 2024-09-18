//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

interface INGU404 is IERC165 {
  error NotFound();
  error InvalidTokenId();
  error AlreadyExists();
  error InvalidRecipient();
  error InvalidSender();
  error InvalidSpender();
  error InvalidOperator();
  error UnsafeRecipient();
  error RecipientIsERC721TransferExempt();
  error Unauthorized();
  error InsufficientAllowance();
  error DecimalsTooLow();
  error PermitDeadlineExpired();
  error InvalidSigner();
  error InvalidApproval();
  error OwnedIndexOverflow();
  error MintLimitReached();
  error InvalidExemption();

  function name() external view returns (string memory);

}