{
  description = "Logos zebrad_ui: run and manage a local Zcash node (Zebra).";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    zebrad_module = {
      url = "github:logos-co/logos-zebrad-module";
      inputs.logos-module-builder.follows = "logos-module-builder";
    };
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosQmlModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
