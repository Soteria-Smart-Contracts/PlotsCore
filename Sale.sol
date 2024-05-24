// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract Plots_MultiToken_Presale {
    // Token Addresses
    address public VLND = address(0);
    address public USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    
    // Chainlink Price Feeds
    address public USDTPriceFeed = 0xEe9F2375b4bdF6387aa8265dD4FB8F16512A1d46;

    // Admin Address
    address public Admin;

    // Merkle Root
    bytes32 public MerkleRoot = 0x0;

    // Params
    uint256 public SaleStart;
    uint256 public SaleEnd;
    uint256 public PhaseOnePrice;
    uint256 public PhaseTwoPrice;

    uint256 public TotalRaised;
    uint256 public PhaseOneCap;

    enum SalePhase { AwaitingStart, PhaseOne, PhaseTwo, Over }

    modifier OnlyAdmin() {
        require(msg.sender == Admin, "Only Admin");
        _;
    }

    event TokensPurchased(address indexed buyer, uint256 amount, address token);
    event ProceedsSentToTreasury(uint256 usdtAmount, uint256 usdcAmount, uint256 ethAmount);
    event SaleParamsSet(uint256 saleStart, uint256 saleEnd, uint256 phaseOnePrice, uint256 phaseTwoPrice, uint256 phaseOneCap);
    
    constructor(address admin) {
        Admin = admin;
    }

    // Admin Functions
    function SendProceedsToTreasury() public OnlyAdmin {
        uint256 usdtBalance = IERC20(USDT).balanceOf(address(this));
        uint256 usdcBalance = IERC20(USDC).balanceOf(address(this));
        uint256 ethBalance = address(this).balance;

        IERC20(USDT).transfer(Admin, usdtBalance);
        IERC20(USDC).transfer(Admin, usdcBalance);
        payable(Admin).transfer(ethBalance);

        emit ProceedsSentToTreasury(usdtBalance, usdcBalance, ethBalance);
    }

    function SetSaleParams(
        uint256 saleStart,
        uint256 saleEnd,
        uint256 phaseOnePrice,
        uint256 phaseTwoPrice,
        uint256 phaseOneCap
    ) public OnlyAdmin {
        SaleStart = saleStart;
        SaleEnd = saleEnd;
        PhaseOnePrice = phaseOnePrice;
        PhaseTwoPrice = phaseTwoPrice;
        PhaseOneCap = phaseOneCap;

        emit SaleParamsSet(saleStart, saleEnd, phaseOnePrice, phaseTwoPrice, phaseOneCap);
    }

    // Getter Functions
    function GetSaleStatus() public view returns (SalePhase) {
        if (block.timestamp < SaleStart) {
            return SalePhase.AwaitingStart;
        } else if (block.timestamp > SaleEnd) {
            return SalePhase.Over;
        } else if (TotalRaised < PhaseOneCap) {
            return SalePhase.PhaseOne;
        } else if (TotalRaised >= PhaseOneCap) {
            return SalePhase.PhaseTwo;
        }
        return SalePhase.Over;
    }

    function GetVLNDPrice() public view returns (uint256) {
        if (GetSaleStatus() == SalePhase.PhaseOne) {
            return PhaseOnePrice;
        } else if (GetSaleStatus() == SalePhase.PhaseTwo) {
            return PhaseTwoPrice;
        }
        return 0;
    }

    function ConvertEthToPlots(uint256 amountIn) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(USDTPriceFeed);
        (, int256 priceusdt, , , ) = priceFeed.latestRoundData();
        uint256 USDTEquivalent = (amountIn * uint256(priceusdt)) / 1e8;
        return ConvertStableToPlots(USDTEquivalent);
    }

    function ConvertStableToPlots(uint256 amountIn) public view returns (uint256) {
        return amountIn / GetVLNDPrice();
    }

    // Purchase Functions
    function PurchaseWithEth() public payable {
        require(GetSaleStatus() != SalePhase.Over, "Sale is over");
        uint256 plotsToReceive = ConvertEthToPlots(msg.value);
        require(plotsToReceive > 0, "Invalid amount");
        
        TotalRaised += msg.value;
        IERC20(VLND).transfer(msg.sender, plotsToReceive);

        emit TokensPurchased(msg.sender, plotsToReceive, address(0));
    }

    function PurchaseWithUSDT(uint256 amount) public {
        require(GetSaleStatus() != SalePhase.Over, "Sale is over");
        uint256 plotsToReceive = ConvertStableToPlots(amount);
        require(plotsToReceive > 0, "Invalid amount");
        
        IERC20(USDT).transferFrom(msg.sender, address(this), amount);
        TotalRaised += amount;
        IERC20(VLND).transfer(msg.sender, plotsToReceive);

        emit TokensPurchased(msg.sender, plotsToReceive, USDT);
    }

    function PurchaseWithUSDC(uint256 amount) public {
        require(GetSaleStatus() != SalePhase.Over, "Sale is over");
        uint256 plotsToReceive = ConvertStableToPlots(amount);
        require(plotsToReceive > 0, "Invalid amount");
        
        IERC20(USDC).transferFrom(msg.sender, address(this), amount);
        TotalRaised += amount;
        IERC20(VLND).transfer(msg.sender, plotsToReceive);

        emit TokensPurchased(msg.sender, plotsToReceive, USDC);
    }

    // Utility Functions
    function VerifyWhitelist(bytes32[] memory proof, bytes32 leaf) public view returns (bool) {
        return verify(proof, MerkleRoot, leaf);
    }

    function verify(
        bytes32[] memory proof,
        bytes32 root,
        bytes32 leaf
    ) internal pure returns (bool) {
        bytes32 computedHash = leaf;

        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];

            if (computedHash <= proofElement) {
                computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
            } else {
                computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
            }
        }

        return computedHash == root;
    }
}



interface ERC20 {
  function balanceOf(address owner) external view returns (uint256);
  function allowance(address owner, address spender) external view returns (uint256);
  function approve(address spender, uint value) external returns (bool);
  function Mint(address _MintTo, uint256 _MintAmount) external;
  function transfer(address to, uint value) external returns (bool);
  function transferFrom(address from, address to, uint256 value) external returns (bool); 
  function totalSupply() external view returns (uint);
  function CheckMinter(address AddytoCheck) external view returns(uint);
}

interface AggregatorV3Interface {
  function latestRoundData()
    external
    view
    returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

//Merkle Verification Libraries
library Hashes {
    /**
     * @dev Commutative Keccak256 hash of a sorted pair of bytes32. Frequently used when working with merkle proofs.
     *
     * NOTE: Equivalent to the `standardNodeHash` in our https://github.com/OpenZeppelin/merkle-tree[JavaScript library].
     */
    function commutativeKeccak256(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? _efficientKeccak256(a, b) : _efficientKeccak256(b, a);
    }

    /**
     * @dev Implementation of keccak256(abi.encode(a, b)) that doesn't allocate or expand memory.
     */
    function _efficientKeccak256(bytes32 a, bytes32 b) private pure returns (bytes32 value) {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, a)
            mstore(0x20, b)
            value := keccak256(0x00, 0x40)
        }
    }
}

library MerkleProof {
    /**
     *@dev The multiproof provided is not valid.
     */
    error MerkleProofInvalidMultiproof();

    /**
     * @dev Returns true if a `leaf` can be proved to be a part of a Merkle tree
     * defined by `root`. For this, a `proof` must be provided, containing
     * sibling hashes on the branch from the leaf to the root of the tree. Each
     * pair of leaves and each pair of pre-images are assumed to be sorted.
     */
    function verify(bytes32[] memory proof, bytes32 root, bytes32 leaf) internal pure returns (bool) {
        return processProof(proof, leaf) == root;
    }

    /**
     * @dev Calldata version of {verify}
     */
    function verifyCalldata(bytes32[] calldata proof, bytes32 root, bytes32 leaf) internal pure returns (bool) {
        return processProofCalldata(proof, leaf) == root;
    }

    /**
     * @dev Returns the rebuilt hash obtained by traversing a Merkle tree up
     * from `leaf` using `proof`. A `proof` is valid if and only if the rebuilt
     * hash matches the root of the tree. When processing the proof, the pairs
     * of leafs & pre-images are assumed to be sorted.
     */
    function processProof(bytes32[] memory proof, bytes32 leaf) internal pure returns (bytes32) {
        bytes32 computedHash = leaf;
        for (uint256 i = 0; i < proof.length; i++) {
            computedHash = Hashes.commutativeKeccak256(computedHash, proof[i]);
        }
        return computedHash;
    }

    /**
     * @dev Calldata version of {processProof}
     */
    function processProofCalldata(bytes32[] calldata proof, bytes32 leaf) internal pure returns (bytes32) {
        bytes32 computedHash = leaf;
        for (uint256 i = 0; i < proof.length; i++) {
            computedHash = Hashes.commutativeKeccak256(computedHash, proof[i]);
        }
        return computedHash;
    }

    /**
     * @dev Returns true if the `leaves` can be simultaneously proven to be a part of a Merkle tree defined by
     * `root`, according to `proof` and `proofFlags` as described in {processMultiProof}.
     *
     * CAUTION: Not all Merkle trees admit multiproofs. See {processMultiProof} for details.
     */
    function multiProofVerify(
        bytes32[] memory proof,
        bool[] memory proofFlags,
        bytes32 root,
        bytes32[] memory leaves
    ) internal pure returns (bool) {
        return processMultiProof(proof, proofFlags, leaves) == root;
    }

    /**
     * @dev Calldata version of {multiProofVerify}
     *
     * CAUTION: Not all Merkle trees admit multiproofs. See {processMultiProof} for details.
     */
    function multiProofVerifyCalldata(
        bytes32[] calldata proof,
        bool[] calldata proofFlags,
        bytes32 root,
        bytes32[] memory leaves
    ) internal pure returns (bool) {
        return processMultiProofCalldata(proof, proofFlags, leaves) == root;
    }

    /**
     * @dev Returns the root of a tree reconstructed from `leaves` and sibling nodes in `proof`. The reconstruction
     * proceeds by incrementally reconstructing all inner nodes by combining a leaf/inner node with either another
     * leaf/inner node or a proof sibling node, depending on whether each `proofFlags` item is true or false
     * respectively.
     *
     * CAUTION: Not all Merkle trees admit multiproofs. To use multiproofs, it is sufficient to ensure that: 1) the tree
     * is complete (but not necessarily perfect), 2) the leaves to be proven are in the opposite order they are in the
     * tree (i.e., as seen from right to left starting at the deepest layer and continuing at the next layer).
     */
    function processMultiProof(
        bytes32[] memory proof,
        bool[] memory proofFlags,
        bytes32[] memory leaves
    ) internal pure returns (bytes32 merkleRoot) {
        // This function rebuilds the root hash by traversing the tree up from the leaves. The root is rebuilt by
        // consuming and producing values on a queue. The queue starts with the `leaves` array, then goes onto the
        // `hashes` array. At the end of the process, the last hash in the `hashes` array should contain the root of
        // the Merkle tree.
        uint256 leavesLen = leaves.length;
        uint256 proofLen = proof.length;
        uint256 totalHashes = proofFlags.length;

        // Check proof validity.
        if (leavesLen + proofLen != totalHashes + 1) {
            revert MerkleProofInvalidMultiproof();
        }

        // The xxxPos values are "pointers" to the next value to consume in each array. All accesses are done using
        // `xxx[xxxPos++]`, which return the current value and increment the pointer, thus mimicking a queue's "pop".
        bytes32[] memory hashes = new bytes32[](totalHashes);
        uint256 leafPos = 0;
        uint256 hashPos = 0;
        uint256 proofPos = 0;
        // At each step, we compute the next hash using two values:
        // - a value from the "main queue". If not all leaves have been consumed, we get the next leaf, otherwise we
        //   get the next hash.
        // - depending on the flag, either another value from the "main queue" (merging branches) or an element from the
        //   `proof` array.
        for (uint256 i = 0; i < totalHashes; i++) {
            bytes32 a = leafPos < leavesLen ? leaves[leafPos++] : hashes[hashPos++];
            bytes32 b = proofFlags[i]
                ? (leafPos < leavesLen ? leaves[leafPos++] : hashes[hashPos++])
                : proof[proofPos++];
            hashes[i] = Hashes.commutativeKeccak256(a, b);
        }

        if (totalHashes > 0) {
            if (proofPos != proofLen) {
                revert MerkleProofInvalidMultiproof();
            }
            unchecked {
                return hashes[totalHashes - 1];
            }
        } else if (leavesLen > 0) {
            return leaves[0];
        } else {
            return proof[0];
        }
    }

    /**
     * @dev Calldata version of {processMultiProof}.
     *
     * CAUTION: Not all Merkle trees admit multiproofs. See {processMultiProof} for details.
     */
    function processMultiProofCalldata(
        bytes32[] calldata proof,
        bool[] calldata proofFlags,
        bytes32[] memory leaves
    ) internal pure returns (bytes32 merkleRoot) {
        // This function rebuilds the root hash by traversing the tree up from the leaves. The root is rebuilt by
        // consuming and producing values on a queue. The queue starts with the `leaves` array, then goes onto the
        // `hashes` array. At the end of the process, the last hash in the `hashes` array should contain the root of
        // the Merkle tree.
        uint256 leavesLen = leaves.length;
        uint256 proofLen = proof.length;
        uint256 totalHashes = proofFlags.length;

        // Check proof validity.
        if (leavesLen + proofLen != totalHashes + 1) {
            revert MerkleProofInvalidMultiproof();
        }

        // The xxxPos values are "pointers" to the next value to consume in each array. All accesses are done using
        // `xxx[xxxPos++]`, which return the current value and increment the pointer, thus mimicking a queue's "pop".
        bytes32[] memory hashes = new bytes32[](totalHashes);
        uint256 leafPos = 0;
        uint256 hashPos = 0;
        uint256 proofPos = 0;
        // At each step, we compute the next hash using two values:
        // - a value from the "main queue". If not all leaves have been consumed, we get the next leaf, otherwise we
        //   get the next hash.
        // - depending on the flag, either another value from the "main queue" (merging branches) or an element from the
        //   `proof` array.
        for (uint256 i = 0; i < totalHashes; i++) {
            bytes32 a = leafPos < leavesLen ? leaves[leafPos++] : hashes[hashPos++];
            bytes32 b = proofFlags[i]
                ? (leafPos < leavesLen ? leaves[leafPos++] : hashes[hashPos++])
                : proof[proofPos++];
            hashes[i] = Hashes.commutativeKeccak256(a, b);
        }

        if (totalHashes > 0) {
            if (proofPos != proofLen) {
                revert MerkleProofInvalidMultiproof();
            }
            unchecked {
                return hashes[totalHashes - 1];
            }
        } else if (leavesLen > 0) {
            return leaves[0];
        } else {
            return proof[0];
        }
    }
}
