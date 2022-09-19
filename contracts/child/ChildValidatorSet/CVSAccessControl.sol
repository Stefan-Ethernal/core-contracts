// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "../../common/Owned.sol";
import "../../interfaces/ChildValidatorSet/ICVSAccessControl.sol";
import "./CVSStorage.sol";

contract CVSAccessControl is ICVSAccessControl, CVSStorage, Owned {
    /**
     * @inheritdoc ICVSAccessControl
     */
    function addToWhitelist(address[] calldata whitelistAddreses) external onlyOwner {
        for (uint256 i = 0; i < whitelistAddreses.length; i++) {
            _addToWhitelist(whitelistAddreses[i]);
        }
    }

    /**
     * @inheritdoc ICVSAccessControl
     */
    function removeFromWhitelist(address[] calldata whitelistAddreses) external onlyOwner {
        for (uint256 i = 0; i < whitelistAddreses.length; i++) {
            _removeFromWhitelist(whitelistAddreses[i]);
        }
    }

    function _addToWhitelist(address account) internal {
        whitelist[account] = true;
        emit AddedToWhitelist(account);
    }

    function _removeFromWhitelist(address account) internal {
        whitelist[account] = false;
        emit RemovedFromWhitelist(account);
    }
}
