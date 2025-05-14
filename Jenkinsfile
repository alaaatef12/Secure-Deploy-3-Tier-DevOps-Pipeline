pipeline {
    agent any

    triggers {
        GenericTrigger(
            genericVariables: [
                [key: 'GIT_COMMIT', value: '$GIT_COMMIT'],
                [key: 'GOGS_REPO', value: '$GOGS_REPO']
            ],
            causeString: 'Triggered by Gogs commit',
            token: 'your-jenkins-webhook-token'
        )
    }

    stages {
        stage('Run Apache Playbook') {
            steps {
                script {
                    ansiblePlaybook(
                        playbook: 'InstallApache.yml',
                        inventory: 'path/to/inventory/file',
                        extraVars: [ansible_user: 'your_user']
                    )
                }
            }
        }

        stage('Docker Image Build') {
            steps {
                script {
                    // Build Docker Image
                    def image = docker.build("nginx-custom")

                    // Save the Docker image to a tar file
                    sh 'docker save nginx-custom > nginx-custom.tar'
                }
            }
        }

        stage('Email Notification') {
            post {
                always {
                    script {
                        def dateTime = new Date().format('yyyy-MM-dd HH:mm:ss')
                        emailext(
                            subject: "Pipeline Result: ${currentBuild.currentResult}",
                            body: """
                            Pipeline execution status: ${currentBuild.currentResult}
                            Date and time: ${dateTime}
                            """,
                            to: 'your_email@example.com'
                        )
                    }
                }
            }
        }
    }
}
