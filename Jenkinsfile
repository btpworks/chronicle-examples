pipeline {
  agent any

  options {
    ansiColor('xterm')
    timestamps()
    buildDiscarder(logRotator(daysToKeepStr: '31'))
  }

  environment {
    ISOLATION_ID = sh(returnStdout: true, script: 'echo $BUILD_TAG | sha256sum | cut -c1-64').trim()
  }

  stages {
    stage('Fetch Tags') {
      steps {
        checkout([$class: 'GitSCM', branches: [[name: "${GIT_BRANCH}"]],
            doGenerateSubmoduleConfigurations: false, extensions: [], submoduleCfg: [],
            userRemoteConfigs: [[credentialsId: 'github-credentials',noTags:false, url: "${GIT_URL}"]],
            extensions: [
                  [$class: 'CloneOption',
                  shallow: false,
                  noTags: false,
                  timeout: 60]
            ]])
      }
    }


    stage('Build') {
      steps {
      }
    }

    stage('Test') {
      steps {
        sh '''
          make test-e2e
        '''
        step([$class: "TapPublisher", testResults: "build/results.tap"])
      }
    }



    stage('Package') {
      steps {
      }
    }

    stage("Analyze") {
      steps {
      }
    }

    stage('Create Archives') {
      steps {
      }
    }

    stage("Publish") {
    }
  }

  post {
    always {
        recordIssues enabledForFailure: true, tool: cpd(pattern: '**/build/cpd.xml')
    }
    success {
      echo "Successfully completed"
    }
    aborted {
        error "Aborted, exiting now"
    }
    failure {
        error "Failed, exiting now"
    }
  }
}
