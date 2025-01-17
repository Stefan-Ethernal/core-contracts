# IExitHelper

*@QEDK (Polygon Technology)*

> ExitHelper

Helper contract to process exits from stored event roots in CheckpointManager



## Methods

### batchExit

```solidity
function batchExit(IExitHelper.BatchExitInput[] inputs) external nonpayable
```





#### Parameters

| Name | Type | Description |
|---|---|---|
| inputs | IExitHelper.BatchExitInput[] | undefined |

### caller

```solidity
function caller() external view returns (address)
```

Returns the address that called the exit function

*only available in the context of the exit function*


#### Returns

| Name | Type | Description |
|---|---|---|
| _0 | address | address of the caller |

### exit

```solidity
function exit(uint256 blockNumber, uint256 leafIndex, bytes unhashedLeaf, bytes32[] proof) external nonpayable
```

Perform an exit for one event



#### Parameters

| Name | Type | Description |
|---|---|---|
| blockNumber | uint256 | Block number of the exit event on L2 |
| leafIndex | uint256 | Index of the leaf in the exit event Merkle tree |
| unhashedLeaf | bytes | ABI-encoded exit event leaf |
| proof | bytes32[] | Proof of the event inclusion in the tree |




