# Download Repo and Remove Files Ignored in .dockerignore

This was created as a hack to remove files based on a .dockerignore when replicating an intranet repo to an internet repo.

The primary motivation for this came from having to build and deploy a machine learning model. During training time (think of it as a build phase), the repo has to contain business data, but during serving time (deployed app), there is no business data.

In this case, the training / build phase is done within a company's own intranet network, but the serving / deploy phase is exposed in the public internet.

As a result, we have 2 repos, one intranet, and one internet. The machine learning model training phase produces artifacts which are stored in the intranet repo. This repo is then replicated onto the internet repo, to build a Docker image to serve the model. Unfortunately the intranet repo also contains some business data (due to Jupyter Noteboooks storing the cell outputs which may contain business data) - these files should not be stored in the Internet repo. There are also other files which are redundant and unused in the Docker image, which we can also remove.

So, this first clones the intranet repo, then removes the unwanted files, then creates a zip file with only the required files to be pushed to the internet repo.

## How to Use

Download the `custom-download.sh` file into your own repo which you have a similar requirement. The `custom-download.sh` script contains 3 variables which you would need to change: `TEMP_FOLDER`, `OUTPUT_ZIP_FILE`, `REPO`.

- `TEMP_FOLDER` is a temporary folder (which will be cleaned up after the script runs) to store the cloned repo
- `OUTPUT_ZIP_FILE` is the output zip file where you want to save the repo with the files ignored in .dockerignore stripped out
- `REPO` is the most important variable; this is the URL of the repo to clone / download

If you need to, do add certain files which need to be stored in the internet repo but are ignored in .dockerignore e.g. Dockerfile, which normally doesn't need to be in the Docker image and would have been ignored (and hence deleted). For example, after the `cp .dockerignore .gitignore` line, add:

```bash
echo '!Dockerfile' >> .gitignore
```

(or you could create a separate file with similar syntax and echo it into .gitignore, if you have many files to explicitly allow)