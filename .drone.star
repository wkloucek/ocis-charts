config = {
    "branches": [
        "master",
    ],
    # if this changes, also the kubeVersion in the Chart.yaml needs to be changed
    "kubernetesVersions": [
        "1.24.0",
        "1.25.0",
        "1.26.0",
        "1.27.0",
    ],
}

def main(ctx):
    return linting(ctx) + documentation(ctx) + checkStarlark()

def linting(ctx):
    pipelines = []

    kubeconform_steps = []

    for version in config["kubernetesVersions"]:
        kubeconform_steps.append(
            {
                "name": "template - %s" % version,
                "image": "owncloudci/alpine:latest",
                "commands": [
                    "make api-%s-template" % version,
                ],
            },
        )
        kubeconform_steps.append(
            {
                "name": "kubeconform - %s" % version,
                "image": "owncloudci/golang:latest",
                "commands": [
                    "make api-%s-kubeconform" % version,
                ],
                "volumes": [
                    {
                        "name": "gopath",
                        "path": "/go",
                    },
                ],
            },
        )

    result = {
        "kind": "pipeline",
        "type": "docker",
        "name": "lint charts/ocis",
        "steps": [
            {
                "name": "helm lint",
                "image": "owncloudci/alpine:latest",
                "commands": [
                    "helm lint charts/ocis",
                ],
            },
            {
                "name": "helm template",
                "image": "owncloudci/alpine:latest",
                "commands": [
                    "helm template charts/ocis -f 'charts/ocis/ci/values_pre_1.25.0.yaml' > charts/ocis/ci/templated.yaml",
                ],
            },
            {
                "name": "kube-linter",
                "image": "stackrox/kube-linter:latest",
                "entrypoint": [
                    "/kube-linter",
                    "lint",
                    "charts/ocis/ci/templated.yaml",
                ],
            },
        ] + kubeconform_steps,
        "depends_on": [],
        "trigger": {
            "ref": [
                "refs/pull/**",
            ],
        },
        "volumes": [
            {
                "name": "gopath",
                "temp": {},
            },
        ],
    }

    for branch in config["branches"]:
        result["trigger"]["ref"].append("refs/heads/%s" % branch)

    pipelines.append(result)

    return pipelines

def documentation(ctx):
    result = {
        "kind": "pipeline",
        "type": "docker",
        "name": "documentation",
        "steps": [
            {
                "name": "helm-docs-readme",
                "image": "jnorwood/helm-docs:v1.11.0",
                "entrypoint": [
                    "/usr/bin/helm-docs",
                    "--template-files=README.md.gotmpl",
                    "--output-file=README.md",
                ],
            },
            {
                "name": "helm-docs-values-table-adoc",
                "image": "jnorwood/helm-docs:v1.11.0",
                "entrypoint": [
                    "/usr/bin/helm-docs",
                    "--template-files=charts/ocis/docs/templates/values-desc-table.adoc.gotmpl",
                    "--output-file=docs/values-desc-table.adoc",
                ],
            },
            {
                "name": "helm-docs-kube-versions-adoc",
                "image": "jnorwood/helm-docs:v1.11.0",
                "entrypoint": [
                    "/usr/bin/helm-docs",
                    "--template-files=charts/ocis/docs/templates/kube-versions.adoc.gotmpl",
                    "--output-file=kube-versions.adoc",
                ],
            },
            {
                "name": "gomplate-values-adoc",
                "image": "hairyhenderson/gomplate:v3.10.0-alpine",
                "entrypoint": [
                    "/bin/gomplate",
                    "--file=charts/ocis/docs/templates/values.adoc.yaml.gotmpl",
                    "--out=charts/ocis/docs/values.adoc.yaml",
                ],
            },
            {
                "name": "check-unchanged",
                "image": "owncloudci/alpine",
                "commands": [
                    "git diff --exit-code",
                ],
            },
        ],
        "depends_on": [],
        "trigger": {
            "ref": [
                "refs/pull/**",
            ],
        },
    }

    for branch in config["branches"]:
        result["trigger"]["ref"].append("refs/heads/%s" % branch)

    return [result]

def checkStarlark():
    result = {
        "kind": "pipeline",
        "type": "docker",
        "name": "check-starlark",
        "steps": [
            {
                "name": "format-check-starlark",
                "image": "owncloudci/bazel-buildifier:latest",
                "commands": [
                    "buildifier --mode=check .drone.star",
                ],
            },
            {
                "name": "show-diff",
                "image": "owncloudci/bazel-buildifier:latest",
                "commands": [
                    "buildifier --mode=fix .drone.star",
                    "git diff",
                ],
                "when": {
                    "status": [
                        "failure",
                    ],
                },
            },
        ],
        "depends_on": [],
        "trigger": {
            "ref": [
                "refs/pull/**",
            ],
        },
    }

    for branch in config["branches"]:
        result["trigger"]["ref"].append("refs/heads/%s" % branch)

    return [result]
