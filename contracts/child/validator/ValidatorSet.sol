// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import "../../lib/WithdrawalQueue.sol";
import "../../interfaces/child/validator/IValidatorSet.sol";
import "../../interfaces/IStateSender.sol";
import "../../child/NetworkParams.sol";
import "../System.sol";

///@dev Inherits a modified version of `ERC20VotesUpgradeable` with a shifted storage layout.
contract ValidatorSet is IValidatorSet, ERC20VotesUpgradeable, System {
    using WithdrawalQueueLib for WithdrawalQueue;

    bytes32 private constant _STAKE_SIG = keccak256("STAKE");
    bytes32 private constant _UNSTAKE_SIG = keccak256("UNSTAKE");
    bytes32 private constant _SLASH_SIG = keccak256("SLASH");
    uint256 public constant SLASHING_PERCENTAGE = 50; // to be read through NetworkParams later
    uint256 public constant SLASH_INCENTIVE_PERCENTAGE = 30; // exitor reward, to be read through NetworkParams later

    IStateSender private _stateSender;
    address private _stateReceiver;
    address private _rootChainManager;

    uint256 public currentEpochId;

    mapping(uint256 => Epoch) public epochs;
    uint256[] public epochEndBlocks;
    mapping(address => WithdrawalQueue) private _withdrawals;

    NetworkParams private _networkParams;
    mapping(uint256 => uint256) private _commitBlockNumbers;

    mapping(uint256 => bool) public slashProcessed;

    function initialize(
        address newStateSender,
        address newStateReceiver,
        address newRootChainManager,
        address newNetworkParams,
        ValidatorInit[] memory initialValidators
    ) public initializer {
        require(
            newStateSender != address(0) && newStateReceiver != address(0) && newRootChainManager != address(0),
            "INVALID_INPUT"
        );
        __ERC20Permit_init("ValidatorSet");
        __ERC20_init("ValidatorSet", "VSET");
        _stateSender = IStateSender(newStateSender);
        _stateReceiver = newStateReceiver;
        _rootChainManager = newRootChainManager;
        _networkParams = NetworkParams(newNetworkParams);
        for (uint256 i = 0; i < initialValidators.length; ) {
            _stake(initialValidators[i].addr, initialValidators[i].stake);
            unchecked {
                ++i;
            }
        }
        epochEndBlocks.push(0);
        currentEpochId = 1;
    }

    /**
     * @inheritdoc IValidatorSet
     */
    function commitEpoch(uint256 id, Epoch calldata epoch, uint256 epochSize) external onlySystemCall {
        uint256 newEpochId = currentEpochId++;
        require(id == newEpochId, "UNEXPECTED_EPOCH_ID");
        require(epoch.endBlock > epoch.startBlock, "NO_BLOCKS_COMMITTED");
        require((epoch.endBlock - epoch.startBlock + 1) % epochSize == 0, "EPOCH_MUST_BE_DIVISIBLE_BY_EPOCH_SIZE");
        require(epochs[newEpochId - 1].endBlock + 1 == epoch.startBlock, "INVALID_START_BLOCK");
        epochs[newEpochId] = epoch;
        _commitBlockNumbers[newEpochId] = block.number;
        epochEndBlocks.push(epoch.endBlock);
        emit NewEpoch(id, epoch.startBlock, epoch.endBlock, epoch.epochRoot);
    }

    /**
     * @inheritdoc IValidatorSet
     */
    function slash(address[] calldata validators) external onlySystemCall {
        _stateSender.syncState(
            _rootChainManager,
            abi.encode(_SLASH_SIG, validators, SLASHING_PERCENTAGE, SLASH_INCENTIVE_PERCENTAGE)
        );
    }

    function onStateReceive(uint256 /*counter*/, address sender, bytes calldata data) external override {
        require(msg.sender == _stateReceiver && sender == _rootChainManager, "INVALID_SENDER");
        if (bytes32(data[:32]) == _STAKE_SIG) {
            (address validator, uint256 amount) = abi.decode(data[32:], (address, uint256));
            _stake(validator, amount);
        } else if (bytes32(data[:32]) == _SLASH_SIG) {
            (, uint256 exitEventId, address[] memory validatorsToSlash, ) = abi.decode(
                data,
                (bytes32, uint256, address[], uint256)
            );
            _slash(exitEventId, validatorsToSlash);
        }
    }

    /**
     * @inheritdoc IValidatorSet
     */
    function unstake(uint256 amount) external {
        _burn(msg.sender, amount);
        _registerWithdrawal(msg.sender, amount);
    }

    /**
     * @inheritdoc IValidatorSet
     */
    function withdraw() external {
        WithdrawalQueue storage queue = _withdrawals[msg.sender];
        (uint256 amount, uint256 newHead) = queue.withdrawable(currentEpochId);
        queue.head = newHead;
        emit Withdrawal(msg.sender, amount);
        _stateSender.syncState(_rootChainManager, abi.encode(_UNSTAKE_SIG, msg.sender, amount));
    }

    /**
     * @inheritdoc IValidatorSet
     */
    // slither-disable-next-line unused-return
    function withdrawable(address account) external view returns (uint256 amount) {
        (amount, ) = _withdrawals[account].withdrawable(currentEpochId);
    }

    /**
     * @inheritdoc IValidatorSet
     */
    function pendingWithdrawals(address account) external view returns (uint256) {
        return _withdrawals[account].pending(currentEpochId);
    }

    /**
     * @inheritdoc IValidatorSet
     */
    function totalBlocks(uint256 epochId) external view returns (uint256 length) {
        uint256 endBlock = epochs[epochId].endBlock;
        length = endBlock == 0 ? 0 : endBlock - epochs[epochId].startBlock + 1;
    }

    function balanceOfAt(address account, uint256 epochNumber) external view returns (uint256) {
        return super.getPastVotes(account, _commitBlockNumbers[epochNumber]);
    }

    function totalSupplyAt(uint256 epochNumber) external view returns (uint256) {
        return super.getPastTotalSupply(_commitBlockNumbers[epochNumber]);
    }

    function _registerWithdrawal(address account, uint256 amount) internal {
        _withdrawals[account].append(amount, currentEpochId + _networkParams.withdrawalWaitPeriod());
        emit WithdrawalRegistered(account, amount);
    }

    function _slash(uint256 exitEventId, address[] memory validatorsToSlash) internal {
        require(!slashProcessed[exitEventId], "SLASH_ALREADY_PROCESSED"); // sanity check
        slashProcessed[exitEventId] = true;
        uint256 length = validatorsToSlash.length;
        for (uint256 i = 0; i < length; ) {
            _burn(validatorsToSlash[i], balanceOf(validatorsToSlash[i])); // unstake validator
            // slither-disable-next-line mapping-deletion
            delete _withdrawals[validatorsToSlash[i]]; // remove pending withdrawals
            unchecked {
                ++i;
            }
        }
        emit Slashed(exitEventId, validatorsToSlash);
    }

    function _stake(address validator, uint256 amount) internal {
        assert(balanceOf(validator) + amount <= _maxSupply());
        _mint(validator, amount);
        _delegate(validator, validator);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        require(from == address(0) || to == address(0), "TRANSFER_FORBIDDEN");
        super._beforeTokenTransfer(from, to, amount);
    }

    function _delegate(address delegator, address delegatee) internal override {
        if (delegator != delegatee) revert("DELEGATION_FORBIDDEN");
        super._delegate(delegator, delegatee);
    }
}
