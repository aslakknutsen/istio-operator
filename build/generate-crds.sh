#!/usr/bin/env bash

set -e -u

: "${MAISTRA_VERSION:?"Need to set maistra version, e.g. 2.0.1"}"
BUNDLE_DIRS="manifests-maistra/${MAISTRA_VERSION} manifests-servicemesh/${MAISTRA_VERSION}"

for bundle_dir in ${BUNDLE_DIRS}; do
  mkdir -p "$bundle_dir"
done

function generateCRDs() {
  echo "Generating CRDs"
  go run -mod=vendor sigs.k8s.io/controller-tools/cmd/controller-gen crd \
      paths=./pkg/apis/maistra/... \
      crd:maxDescLen=0,preserveUnknownFields=false,crdVersions=v1 \
      output:dir=./deploy/crds

# FIXME: Remove when generating v1 above
 echo "Removing default values"
 sed -i '/default: TCP/d' deploy/crds/*

  echo "Patching CRDs to add attributes not supported by controller-gen"
   # workaround for https://github.com/kubernetes-sigs/controller-tools/issues/457
  #sed -i -e "s/\( *\)\(description\: The IP protocol for this port\)/\1default: TCP\n\1\2/" \
  #    deploy/crds/maistra.io_servicemeshcontrolplanes.yaml
  sed -i -e '/x-kubernetes-list-map-keys:/,/x-kubernetes-list-type: map/ { /- protocol/d }' deploy/crds/maistra.io_servicemeshcontrolplanes.yaml

  # The data generated by the OLM tooling adds a number of dashes to the top that don't parse properly. This fixes it.
  sed -i -e '/---/d' deploy/crds/*

  # Add maistra-version label
  sed -i -e "s/^  annotations:/  labels:\n    maistra-version: $MAISTRA_VERSION\n\\0/" deploy/crds/*

  sed -i -e 's/^  annotations:/  annotations:\n    service.beta.openshift.io\/inject-cabundle: "true"/' \
      deploy/crds/maistra.io_servicemeshcontrolplanes.yaml

  for bundle_dir in ${BUNDLE_DIRS}; do
    echo "Writing CRDs to directory ${bundle_dir}"
    cp deploy/crds/maistra.io_servicemeshcontrolplanes.yaml "${bundle_dir}/servicemeshcontrolplanes.crd.yaml"
    cp deploy/crds/maistra.io_servicemeshmemberrolls.yaml "${bundle_dir}/servicemeshmemberrolls.crd.yaml"
    cp deploy/crds/maistra.io_servicemeshmembers.yaml "${bundle_dir}/servicemeshmembers.crd.yaml"
  done

  echo "Writing CRDs to file deploy/src/crd.yaml"
  { cat deploy/crds/maistra.io_servicemeshcontrolplanes.yaml; echo -e "\n---\n";
    cat deploy/crds/maistra.io_servicemeshmemberrolls.yaml;  echo -e "\n---\n";
    cat deploy/crds/maistra.io_servicemeshmembers.yaml; } >deploy/src/crd.yaml

  rm -rf deploy/crds/
}

generateCRDs
