## Balance Shares Protocol

Author: Ben Jett (@BCJdevelopment)

An EVM singleton protocol that allows any client to manage account shares for any given balance share (such as a revenue share, a profit share, etc). Allows clients to:
- Create/update account shares with basis point (BPS) shares and lock periods for any uint256 balance share ID
- Allocate balances of ETH or any ERC20 asset to this protocol contract for each balance share to be withdrawable by the account share recipients
- Update/add/remove account shares at any time, without needing to create a new balance share ID

The point of this protocol is to make balance share allocations as gas-efficient as possible for a smart contract's users, offloading the heavier gas operations to each account share recipient's withdrawal logic. It also makes it easier to have one place to manage all accounts for a balance share, without needing to deploy new revenue splitting contracts to update the account shares involved.

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```
