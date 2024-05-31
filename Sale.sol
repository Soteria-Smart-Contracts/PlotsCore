// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

contract Plots_MultiToken_Presale {
    // Token Addresses
    address public VLND = address(0);
    address public USDT = 0xaA8E23Fb1079EA71e0a56F48a2aA51851D8433D0;
    address public USDC = 0xf08A50178dfcDe18524640EA6618a1f965821715;
    
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

    enum UserType { TwentyFiveFDV, FifteenFDV }

    modifier OnlyAdmin() {
        require(msg.sender == Admin, "Only Admin");
        _;
    }

    event TokensPurchased(address indexed buyer, uint256 amount, address token);
    event ProceedsSentToTreasury(uint256 usdtAmount, uint256 usdcAmount, uint256 ethAmount);
    event SaleParamsSet(uint256 saleStart, uint256 saleEnd, uint256 phaseOnePrice, uint256 phaseTwoPrice, uint256 phaseOneCap);

    constructor(
        uint256 saleStart,
        uint256 saleEnd,
        uint256 phaseOnePrice,
        uint256 phaseTwoPrice,
        uint256 phaseOneCap,
        address admin
        ) {
        SaleStart = saleStart;
        SaleEnd = saleEnd;
        PhaseOnePrice = phaseOnePrice;
        PhaseTwoPrice = phaseTwoPrice;
        PhaseOneCap = phaseOneCap;
        Admin = admin;

        //deploy a new erc20 token called vlnd, set the max tokens to 1 million convert to wei and set the vlnd address to the new token address
        ERC20 token = new ERC20(1000000, "VLND", "VLND");
        token.ManageMinter(true, address(this));
        VLND = address(token);

        emit SaleParamsSet(saleStart, saleEnd, phaseOnePrice, phaseTwoPrice, phaseOneCap);
    }

    // Admin Functions
    function SendProceedsToTreasury() public OnlyAdmin {
        uint256 usdtBalance = ERC20(USDT).balanceOf(address(this));
        uint256 usdcBalance = ERC20(USDC).balanceOf(address(this));
        uint256 ethBalance = address(this).balance;

        ERC20(USDT).transfer(Admin, usdtBalance);
        ERC20(USDC).transfer(Admin, usdcBalance);
        payable(Admin).transfer(ethBalance);

        emit ProceedsSentToTreasury(usdtBalance, usdcBalance, ethBalance);
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
        revert("Sale is not in Phase One or Phase Two");
    }

    function ConvertEthToPlots(uint256 amountIn) public view returns (uint256) {
        uint256 StableEquivalent = ConvertEthToStable(amountIn);
        return ConvertStableToPlots(StableEquivalent);
    }

    //convert eth to stable
    function ConvertEthToStable(uint256 amountIn) public view returns (uint256) {
        //AggregatorV3Interface priceFeed = AggregatorV3Interface(USDTPriceFeed);
        //(, int256 priceusdt, , , ) = priceFeed.latestRoundData();
        uint256 priceusdt = 261650782927308;
        return (amountIn * uint256(priceusdt)) / 1e8;
    }

    function ConvertStableToPlots(uint256 amountIn) public view returns (uint256) {
        return amountIn / GetVLNDPrice();
    }

    // Purchase Functions
    function PurchaseWithETH(UserType PhaseRequested, uint256 UserPoints, bytes32 Proof) public payable {
        require(GetSaleStatus() != SalePhase.Over, "Sale is over");
        uint256 plotsToReceive = ConvertEthToPlots(msg.value);
        require(plotsToReceive > 0, "Invalid amount");
        //each point is worth 50 cents, and the number of points determins the max number of plots you can buy, so make sure the eth amount does not exceed the max amount of plots you can buy
        require(UserPoints / 2 >= ConvertEthToStable(msg.value), "Invalid amount");

        if (PhaseRequested == UserType.TwentyFiveFDV) {
            require(VerifyCredentials(Proof, keccak256(abi.encodePacked(msg.sender))), "Invalid credentials");
        } else if (PhaseRequested == UserType.FifteenFDV) {
            require(VerifyCredentials(Proof, keccak256(abi.encodePacked(StringUtils.concatenate(msg.sender, UserPoints)))), "Invalid credentials");
        }
        
        TotalRaised += msg.value;
        ERC20(VLND).transfer(msg.sender, plotsToReceive);

        emit TokensPurchased(msg.sender, plotsToReceive, address(0));
    }

    function PurchaseWithUSDT(uint256 amount, UserType PhaseRequested, uint256 UserPoints, bytes32 Proof) public {
        require(GetSaleStatus() != SalePhase.Over, "Sale is over");
        uint256 plotsToReceive = ConvertStableToPlots(amount);
        require(plotsToReceive > 0, "Invalid amount");
        require(UserPoints / 2 >= amount, "Invalid amount");

        if (PhaseRequested == UserType.TwentyFiveFDV) {
            require(VerifyCredentials(Proof, keccak256(abi.encodePacked(msg.sender))), "Invalid credentials");
        } else if (PhaseRequested == UserType.FifteenFDV) {
            require(VerifyCredentials(Proof, keccak256(abi.encodePacked(StringUtils.concatenate(msg.sender, UserPoints)))), "Invalid credentials");
        }
        
        ERC20(USDT).transferFrom(msg.sender, address(this), amount);
        TotalRaised += amount;
        ERC20(VLND).Mint(msg.sender, plotsToReceive);

        emit TokensPurchased(msg.sender, plotsToReceive, USDT);
    }

    function PurchaseWithUSDC(uint256 amount, UserType PhaseRequested, uint256 UserPoints, bytes32 Proof) public {
        require(GetSaleStatus() != SalePhase.Over, "Sale is over");
        uint256 plotsToReceive = ConvertStableToPlots(amount);
        require(plotsToReceive > 0, "Invalid amount");
        require(UserPoints / 2 >= amount, "Invalid amount");
        
        ERC20(USDC).transferFrom(msg.sender, address(this), amount);
        TotalRaised += amount;
        ERC20(VLND).Mint(msg.sender, plotsToReceive);

        emit TokensPurchased(msg.sender, plotsToReceive, USDC);
    }

    // Utility Functions
    //verify sale eligibility via credentials view function that takes in a user type a user points value and an address and returns a boolean

    function VerifyCredentials(bytes32[] memory proof, bytes32 leaf) public view returns (bool) {
        return verify(proof, MerkleRoot, leaf);
    }

    function VerifyCredentials(bytes32[] memory proof, bytes32 leaf) public view returns (bool) {
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


contract ERC20 {
    uint256 public tokenCap;
    uint256 public totalSupply;
    string public name;
    string public symbol;
    uint8 public decimals;
    address private operator;
    address private ZeroAddress;
    //variable Declarations
    
      
    event Transfer(address indexed from, address indexed to, uint256 value);    
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event BurnEvent(address indexed burner, uint256 indexed buramount);
    event ManageMinterEvent(address indexed newminter);
    //Event Declarations 
    
    mapping(address => uint256) balances;

    mapping(address => mapping (address => uint256)) public allowance;
    
    mapping(address => bool) minter;
    
    constructor(uint256 _TokenCap, string memory _name, string memory _symbol){
        tokenCap = _TokenCap;
        totalSupply = 0;
        name = _name;
        symbol = _symbol;
        decimals = 18;
        operator = msg.sender;
    }
    
    
    function balanceOf(address Address) public view returns (uint256 balance){
        return balances[Address];

    }

    function approve(address delegate, uint _amount) public returns (bool) {
        allowance[msg.sender][delegate] = _amount;
        emit Approval(msg.sender, delegate, _amount);
        return true;
    }
    //Approves an address to spend your coins

    function transferFrom(address _from, address _to, uint256 _amount) public returns (bool) {
        require(_amount <= balances[_from]);    
        require(_amount <= allowance[_from][msg.sender]); 
    
        balances[_from] = balances[_from]-(_amount);
        allowance[_from][msg.sender] = allowance[_from][msg.sender]-(_amount);
        balances[_to] = balances[_to]+(_amount);
        emit Transfer(_from, _to, _amount);
        return true;
    }
    //Transfer From an other address


    function transfer(address _to, uint256 _amount) public returns (bool) {
        require(_amount <= balances[msg.sender]);
        balances[msg.sender] = balances[msg.sender]-(_amount);
        balances[_to] = balances[_to]+(_amount);
        emit Transfer(msg.sender, _to, _amount);
        return true;
    }


    function Mint(address _MintTo, uint256 _MintAmount) public {
        require (minter[msg.sender] == true);
        require (totalSupply+(_MintAmount) <= tokenCap);
        balances[_MintTo] = balances[_MintTo]+(_MintAmount);
        totalSupply = totalSupply+(_MintAmount);
        ZeroAddress = 0x0000000000000000000000000000000000000000;
        emit Transfer(ZeroAddress ,_MintTo, _MintAmount);
    }
    //Mints tokens to your address 


    function Burn(uint256 _BurnAmount) public {
        require (balances[msg.sender] >= _BurnAmount);
        balances[msg.sender] = balances[msg.sender]-(_BurnAmount);
        totalSupply = totalSupply-(_BurnAmount);
        ZeroAddress = 0x0000000000000000000000000000000000000000;
        emit Transfer(msg.sender, ZeroAddress, _BurnAmount);
        emit BurnEvent(msg.sender, _BurnAmount);
        
    }

    function ManageMinter(bool IsMinter, address _address) public returns(address){
        require (msg.sender == operator);

        minter[_address] = IsMinter;

        emit ManageMinterEvent(_address);
        return (_address);
    }

}

interface AggregatorV3Interface {
  function latestRoundData()
    external
    view
    returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library StringUtils {
    // Convert address to string
    function addressToString(address _addr) internal pure returns (string memory) {
        bytes32 value = bytes32(uint256(uint160(_addr)));
        bytes memory alphabet = "0123456789abcdef";

        bytes memory str = new bytes(42);
        str[0] = '0';
        str[1] = 'x';
        for (uint i = 0; i < 20; i++) {
            str[2 + i * 2] = alphabet[uint(uint8(value[i + 12] >> 4))];
            str[3 + i * 2] = alphabet[uint(uint8(value[i + 12] & 0x0f))];
        }
        return string(str);
    }

    // Convert uint256 to string
    function uintToString(uint256 _value) internal pure returns (string memory) {
        if (_value == 0) {
            return "0";
        }
        uint256 temp = _value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (_value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(_value % 10)));
            _value /= 10;
        }
        return string(buffer);
    }

    // Function to concatenate address and points
    function concatenate(address _addr, uint256 _points) internal pure returns (string memory) {
        string memory addrStr = addressToString(_addr);
        string memory pointsStr = uintToString(_points);
        return string(abi.encodePacked(addrStr, pointsStr));
    }
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
