interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function mint(address to, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

library MerkleProof {
    function verify(
        bytes32[] memory proof,
        bytes32 root,
        bytes32 leaf
    ) internal pure returns (bool) {
        bytes32 computedHash = leaf;
        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];

            if (computedHash <= proofElement) {
                // Hash(current computed hash + current proof element)
                computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
            } else {
                // Hash(current proof element + current computed hash)
                computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
            }
        }

        // Verify the computed hash matches the root
        return computedHash == root;
    }
}


contract PlotsFinance {
    uint256 public totalSupply;
    uint256 public maxSupply;
    string public name;
    string public symbol;
    uint8 public decimals;
    address private ZeroAddress;
    address public distributor;
    //variable Declarations
      
    event Transfer(address indexed from, address indexed to, uint256 value);    
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event BurnEvent(address indexed burner, uint256 indexed buramount);
    
    mapping(address => uint256) balances;

    mapping(address => mapping (address => uint256)) public allowance;
    
    
    constructor(string memory _name, string memory _symbol){
        totalSupply = 0;
        name = _name;
        symbol = _symbol;
        decimals = 18;
        distributor = 0x0000000000000000000000000000000000000000;
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


    function transfer(address _to, uint256 _amount) public returns (bool) {
        require(_amount <= balances[msg.sender]);
        balances[msg.sender] = balances[msg.sender]-(_amount);
        balances[_to] = balances[_to]+(_amount);
        emit Transfer(msg.sender, _to, _amount);
        return true;
    }


    function Mint(address _MintTo, uint256 _MintAmount) public {
        require(msg.sender == distributor);
        require(totalSupply+(_MintAmount) <= maxSupply);
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



}