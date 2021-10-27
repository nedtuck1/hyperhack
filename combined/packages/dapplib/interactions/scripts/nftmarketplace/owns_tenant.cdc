import NFTMarketplace from "../../../contracts/Project/NFTMarketplace.cdc"

pub fun main(tenantOwner: Address): String {
    let TenantPackage = getAccount(tenantOwner).getCapability(NFTMarketplace.PackagePublicPath)
                                .borrow<&NFTMarketplace.Package{NFTMarketplace.PackagePublic}>()
                                ?? panic("Could not borrow the public SimpleNFT.Package")
    let TenantID = tenantOwner.toString().concat(".").concat(TenantPackage.uuid.toString())
    return tenantOwner.toString().concat(".").concat(TenantPackage.uuid.toString())
}