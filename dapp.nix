dapp: with dapp; solidityPackage {
  name = "ds-chief";
  deps = with dappsys; [ds-roles ds-test ds-thing ds-token];
  src = ./src;
}
