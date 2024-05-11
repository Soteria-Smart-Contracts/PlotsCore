console.log('merklegen.js loaded');

//convert the whitelistAddresses to an array of addresses with the points number appended to the address end
let ClaimantAddresses = data1.map((address) => {
  return address.address + address.points;
});

let WhitelistAddresses = data2.map((address) => {
  return address.address;
});


const leafNodes = whitelistAddresses.map(addr => keccak256(addr));
let ClaimantsMerkleTree = new MerkleTree(leafNodes, keccak256, { sortPairs: true});

//convert the merkle tree back to a MerkleTree object using the MerkleTree string
let WhitelistMerkleTree = new MerkleTree(JSON.parse(merkleTree), keccak256, { sortPairs: true});

// Get root hash of the `merkleeTree` in hexadecimal format (0x)
// Print out the Entire Merkle Tree.
const rootHash = merkleTree.getRoot();
const rootHashBytes32 = '0x' + merkleTree.getRoot().toString('hex');
console.log("Root Hash Claimants: ", rootHashBytes32);

// ***** ***** ***** ***** ***** ***** ***** ***** // 

// Function to generate hex proof for a claiming address
function generateHexProof(claimingAddress) {
  // `getHexProof` returns the neighbour leaf and all parent nodes hashes that will

  //convert the claimingAddress to an address with the points number appended to the address end and then hash it
  claimingAddress = keccak256(claimingAddress);
  // be required to derive the Merkle Trees root hash.
  const hexProof = merkleTree.getHexProof(claimingAddress);

  // ✅ - ❌: Verify if claiming address is in the merkle tree or not.
  // This would be implemented in your Solidity Smart Contract
  const isAddressInTree = merkleTree.verify(hexProof, claimingAddress, rootHash);

  return {
    hexProof: hexProof,
    isAddressInTree: isAddressInTree
  };
}