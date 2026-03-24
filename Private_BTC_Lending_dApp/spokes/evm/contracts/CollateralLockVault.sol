// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title CollateralLockVault
/// @notice Ethereum/BNB spoke vault for Starknet hub collateral proofs.
contract CollateralLockVault is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    enum AssetKind {
        Native,
        ERC20
    }

    struct LockReceipt {
        address depositor;
        address asset;
        uint256 amount;
        uint64 sourceChainId;
        bytes32 starknetAddressHash;
        uint256 nonce;
        uint256 timestamp;
    }

    event AssetLocked(
        address indexed depositor,
        address indexed asset,
        uint256 amount,
        uint64 indexed sourceChainId,
        bytes32 starknetAddressHash,
        uint256 nonce,
        AssetKind assetKind
    );

    mapping(address => bool) public isAllowedCollateral;
    mapping(uint256 => LockReceipt) public receipts;
    uint256 public nextNonce;

    error InvalidAmount();
    error InvalidStarknetHash();
    error AssetNotAllowed();

    constructor(address owner_) Ownable(owner_) {}

    function setAllowedCollateral(address asset, bool allowed) external onlyOwner {
        isAllowedCollateral[asset] = allowed;
    }

    function lockNative(bytes32 starknetAddressHash) external payable nonReentrant returns (uint256 nonce) {
        if (msg.value == 0) revert InvalidAmount();
        if (starknetAddressHash == bytes32(0)) revert InvalidStarknetHash();

        nonce = _storeReceipt(msg.sender, address(0), msg.value, starknetAddressHash);
        emit AssetLocked(msg.sender, address(0), msg.value, uint64(block.chainid), starknetAddressHash, nonce, AssetKind.Native);
    }

    function lockErc20(address asset, uint256 amount, bytes32 starknetAddressHash)
        external
        nonReentrant
        returns (uint256 nonce)
    {
        if (amount == 0) revert InvalidAmount();
        if (starknetAddressHash == bytes32(0)) revert InvalidStarknetHash();
        if (!isAllowedCollateral[asset]) revert AssetNotAllowed();

        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        nonce = _storeReceipt(msg.sender, asset, amount, starknetAddressHash);

        emit AssetLocked(msg.sender, asset, amount, uint64(block.chainid), starknetAddressHash, nonce, AssetKind.ERC20);
    }

    function _storeReceipt(address depositor, address asset, uint256 amount, bytes32 starknetAddressHash)
        internal
        returns (uint256 nonce)
    {
        nonce = ++nextNonce;
        receipts[nonce] = LockReceipt({
            depositor: depositor,
            asset: asset,
            amount: amount,
            sourceChainId: uint64(block.chainid),
            starknetAddressHash: starknetAddressHash,
            nonce: nonce,
            timestamp: block.timestamp
        });
    }
}
