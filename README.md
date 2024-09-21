# Number Go Up

## How it works...

When users buy an NGU ERC-20 Token (coins), an associated NFT (token) is minted. Tokens have associated ID numbers and rarities which are used to accumulate points via holding and staking. 

All unstaked tokens are kept in the selling queue, a FIFO queue which is used whenever a user burns a token in accordance to the ERC404 standard.

Users can stake the tokens in order to reap the rewards provided by the rarities. Staked tokens can not be sold. When a staked token is unstaked, it is added to the back of the selling queue. 

### Here's an example: 

Player has 3 Coins

Coin 1 - Token Rarity 5

Coin 2 - Token Rarity 1

Coin 3 - Token Rarity 2

Queue is initially constructed in order:

```
SELLING Queue
<Next Sold>[T1, T2, T3]<Last In>
```
Player decides to stake Token 1. A whole coin is transferred from their balance to the contract bank.

```
SELLING Queue
<Next Sold>[T2, T3]<Last In>
```
```
Staked Tokens
[T1]
```

Player unstakes Token 1. A whole coin is tranferred back to the user's balance from the bank. Staked Tokens array is empty.

```
SELLING Queue
<Next Sold>[T2, T3, T1]<Last In>
```

# ToDos and Wishlist
1. Make the NFTs directly sellable - may require an NFT prefix so we can tell the difference between an NFT ID number and an ERC-20 amount.