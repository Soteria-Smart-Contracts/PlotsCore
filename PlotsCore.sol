// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.19;

contract PlotsCore{
    //Variable and pointer Declarations
    address public Treasury;
    address public LendContract;
    address[] public ListedCollections;



    mapping(address => bool) public Admins;
    modifier OnlyAdmin(){
        require(Admins[msg.sender], "Only Admin");
        _;
    }

    mapping(address => uint256[]) public AvailableTokensByCollection;
    mapping(address => mapping(uint256 => uint256)) public AvailableTokensByCollectionIndex;
    mapping(address => uint256) public ListedCollectionsIndex;

    

    constructor(address [] memory _admins){
        Treasury = address(new PlotsTreasury(address(this)));
        for(uint256 i = 0; i < _admins.length; i++){
            Admins[_admins[i]] = true;
        }
    }

    //Public Functions





    function GetAvailableTokensByCollection(address _collection) public view returns(uint256[] memory){
        return AvailableTokensByCollection[_collection];
    }


    //Only Admin Functions

    function ListToken(address Collection, uint256 TokenId, uint256 Value) public OnlyAdmin{
        require(ListedCollectionsIndex[Collection] != 0, "Collection not listed");
        require(AvailableTokensByCollectionIndex[Collection][TokenId] == 0, "Token already listed");
        //require that the treasury or lend contract has the token
        require();

        AvailableTokensByCollection[Collection].push(TokenId);
        AvailableTokensByCollectionIndex[Collection][TokenId] = AvailableTokensByCollection[Collection].length - 1;
    }


    function AddCollection(address _collection) public OnlyAdmin{
        ListedCollections.push(_collection);
        ListedCollectionsIndex[_collection] = ListedCollections.length - 1;
    }

    function RemoveCollection(address _collection) public OnlyAdmin{
        uint256 index = ListedCollectionsIndex[_collection];
        ListedCollections[index] = ListedCollections[ListedCollections.length - 1];
        ListedCollectionsIndex[ListedCollections[index]] = index;
        ListedCollections.pop();
    }
}

contract PlotsTreasury{
    //Variable and pointer Declarations
    address public PlotsCore;

    constructor(address Core){
        PlotsCore = Core;
    }
}



interface ERC721 /* is ERC165 */ {
    function balanceOf(address _owner) external view returns (uint256);
    function ownerOf(uint256 _tokenId) external view returns (address);
    function safeTransferFrom(address _from, address _to, uint256 _tokenId, bytes  data) external payable;
    function safeTransferFrom(address _from, address _to, uint256 _tokenId) external payable;

    /// @notice Transfer ownership of an NFT -- THE CALLER IS RESPONSIBLE
    ///  TO CONFIRM THAT `_to` IS CAPABLE OF RECEIVING NFTS OR ELSE
    ///  THEY MAY BE PERMANENTLY LOST
    /// @dev Throws unless `msg.sender` is the current owner, an authorized
    ///  operator, or the approved address for this NFT. Throws if `_from` is
    ///  not the current owner. Throws if `_to` is the zero address. Throws if
    ///  `_tokenId` is not a valid NFT.
    /// @param _from The current owner of the NFT
    /// @param _to The new owner
    /// @param _tokenId The NFT to transfer
    function transferFrom(address _from, address _to, uint256 _tokenId) external payable;

    /// @notice Change or reaffirm the approved address for an NFT
    /// @dev The zero address indicates there is no approved address.
    ///  Throws unless `msg.sender` is the current NFT owner, or an authorized
    ///  operator of the current owner.
    /// @param _approved The new approved NFT controller
    /// @param _tokenId The NFT to approve
    function approve(address _approved, uint256 _tokenId) external payable;

    /// @notice Enable or disable approval for a third party ("operator") to manage
    ///  all of `msg.sender`'s assets
    /// @dev Emits the ApprovalForAll event. The contract MUST allow
    ///  multiple operators per owner.
    /// @param _operator Address to add to the set of authorized operators
    /// @param _approved True if the operator is approved, false to revoke approval
    function setApprovalForAll(address _operator, bool _approved) external;

    /// @notice Get the approved address for a single NFT
    /// @dev Throws if `_tokenId` is not a valid NFT.
    /// @param _tokenId The NFT to find the approved address for
    /// @return The approved address for this NFT, or the zero address if there is none
    function getApproved(uint256 _tokenId) external view returns (address);

    /// @notice Query if an address is an authorized operator for another address
    /// @param _owner The address that owns the NFTs
    /// @param _operator The address that acts on behalf of the owner
    /// @return True if `_operator` is an approved operator for `_owner`, false otherwise
    function isApprovedForAll(address _owner, address _operator) external view returns (bool);
}

interface ERC165 {
    /// @notice Query if a contract implements an interface
    /// @param interfaceID The interface identifier, as specified in ERC-165
    /// @dev Interface identification is specified in ERC-165. This function
    ///  uses less than 30,000 gas.
    /// @return `true` if the contract implements `interfaceID` and
    ///  `interfaceID` is not 0xffffffff, `false` otherwise
    function supportsInterface(bytes4 interfaceID) external view returns (bool);
}