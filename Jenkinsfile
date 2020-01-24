library(
    identifier: 'pipeline-lib@4.6.1',
    retriever: modernSCM([$class: 'GitSCMSource',
                          remote: 'https://github.com/SmartColumbusOS/pipeline-lib',
                          credentialsId: 'jenkins-github-user'])
)

properties([
    pipelineTriggers([scos.dailyBuildTrigger()]),
    parameters([
        booleanParam(defaultValue: false, description: 'Deploy to development environment?', name: 'DEV_DEPLOYMENT'),
        string(defaultValue: 'development', description: 'Image tag to deploy to dev environment', name: 'DEV_IMAGE_TAG')
    ])
])

def applicationName = "estuary"
def doStageIf = scos.&doStageIf
def doStageIfDeployingToDev = doStageIf.curry(env.DEV_DEPLOYMENT == "true")
def doStageIfMergedToMaster = doStageIf.curry(scos.changeset.isMaster && env.DEV_DEPLOYMENT == "false")
def doStageIfRelease = doStageIf.curry(scos.changeset.isRelease)

node ('infrastructure') {
    ansiColor('xterm') {
        scos.doCheckoutStage()

        doStageIfDeployingToDev('Deploy to Dev') {
            deployTo(applicationName, 'dev', "--set image.tag=${env.DEV_IMAGE_TAG} --recreate-pods")
        }

        doStageIfMergedToMaster('Process Dev job') {
            scos.devDeployTrigger(applicationName)
        }

        doStageIfMergedToMaster('Deploy to Staging') {
            deployTo(applicationName, 'staging')
            scos.applyAndPushGitHubTag('staging')
        }

        doStageIfRelease('Deploy to Production') {
            deployTo(applicationName, 'prod')
            scos.applyAndPushGitHubTag('prod')
        }
    }
}

def deployTo(applicationName, environment, extraArgs = '') {
    scos.withEksCredentials(environment) {
        sh("""#!/bin/bash
            set -e
            helm init --client-only
            helm repo add scdp https://smartcitiesdata.github.io/charts
            helm repo update
            helm upgrade --install ${applicationName} scdp/${applicationName} \
                --version 0.5.0 \
                --namespace=streaming-services \
                --values=${applicationName}.yaml \
                ${extraArgs}
        """.trim())
    }
}