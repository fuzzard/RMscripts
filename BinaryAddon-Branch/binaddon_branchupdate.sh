#!/bin/bash

# Function to set default branch of a given owner/addon repo to NEW_BRANCH
function set_default_branch {
  echo "Setting default branch for GitHub to $NEW_BRANCH"
  # Create api request file
  echo "{" > $ADDON_GH_JSON_REQUEST_FILE
  echo "   \"name\": \"$ADDON_NAME\", ">> $ADDON_GH_JSON_REQUEST_FILE
  echo "   \"default_branch\": \"$NEW_BRANCH\" ">> $ADDON_GH_JSON_REQUEST_FILE
  echo "}" >> $ADDON_GH_JSON_REQUEST_FILE

  if [[ -z "$DRYRUN" ]] ; then
    # Set Default branch of Addon repo to NEW_BRANCH via Github API
    GH_API_RESPONSE=$( { curl -X PATCH -H "Accept: application/vnd.github+json" -H "Authorization: token $PAT_TOKEN" https://api.github.com/repos/$ADDON_REPO_OWNER/$ADDON_NAME --data-binary @$ADDON_GH_JSON_REQUEST_FILE; } 2>&1 >/dev/null )
  fi
}

# Function to cleanup a single file
function rm_file {
  if [ -f $1 ]; then
    rm -f $1
  fi
}

# Function to remove addon from REPO_BINARYADDONS if we are unable to
# update an addon for any reason.
# This will require manual intervention to bring into NEW_BRANCH
function remove_repo_addon {
  echo "Removing $ADDON_NAME from $REPO_BINARYADDONS $NEW_BRANCH"
  rm -rf $PWD/repo-binary-addons/$ADDON_NAME

  COMMIT=$( { cd $PWD/repo-binary-addons && git add --all && git commit -m '['${NEW_BRANCH}'] Remove '${ADDON_NAME}' - Manual Branch intervention required' ; } )
}

REPO_BINARYADDONS=https://github.com/xbmc/repo-binary-addons.git

# Defaults that can be overridden
OLD_BRANCH=Omega
NEW_BRANCH=Piers
VERSION=22.0.0

# Azure Pipelines yml has OLD_BRANCH and OLD_BRANCH-1
# Manually hardcode the previous N-1 branch for now
AZURE_PIPELINE_REMOVE_BRANCH=Nexus

# Temp files
FAIL_FILE=$PWD/failed_repo.txt
ADDON_GH_JSON_REQUEST_FILE=$PWD/gh_request.json
ADDON_GH_JSON_RESPONSE_FILE=$PWD/gh_response.json

# Backup previous fail just in case need to review output
if [ -f $PWD/failed_repo.txt ]; then
  rm -f $PWD/failed_repo.txt.old
  mv $PWD/failed_repo.txt $PWD/failed_repo.txt.old
fi

while getopts :hcdv:o:n:t: flag
do
  case "${flag}" in
    o) OLD_BRANCH=${OPTARG};;
    n) NEW_BRANCH=${OPTARG};;
    v) VERSION=${OPTARG};;
    c) CLEAN=true;;
    d) DRYRUN=true;;
    t) PAT_TOKEN=${OPTARG};;
    h | *) # Display help.
      echo "Usage: $0 [-o <Existing Branch>] [-n <New Branch name>] [-v <New Addon Version>] [-t <GITHUB PAT TOKEN>] [-c] [-d]"
      echo "    -o Name of existing branch to base new branch off"
      echo "    -n Name of new branch"
      echo "    -v Version to substitute into addon xml"
      echo "    -t Github PAT token (required for default branch change)"
      echo "    -c Cleans repo's to start fresh"
      echo "    -d Dry run - Dont push any repos"
      exit 0
      ;;
  esac
done

# Remove existing Repo Folder for clean slate
if [ "$CLEAN" = true ] ; then
    echo Removing $PWD/repo-binary-addons
    rm -rf $PWD/repo-binary-addons
fi

if [ ! -d "$PWD/repo-binary-addons" ];
then
	echo "Cloning $REPO_BINARYADDONS ..."
  git clone $REPO_BINARYADDONS repo-binary-addons &>/dev/null
fi

CHECKOUT=$( { cd $PWD/repo-binary-addons && git checkout $OLD_BRANCH; } 2>&1 >/dev/null )

# Error out if checkout failed
case $CHECKOUT in
  error:*) echo Failed to checkout $OLD_BRANCH. Use -o with an actual Branch name && exit 0;;
esac

unset CHECKOUT

for addon in $PWD/repo-binary-addons/*; do
  if [[ -d "$addon" && ! -L "$addon" ]]; then
    unset ADDON_SUCCESS
    ADDON_DIR=$addon
    ADDON_NAME=$(basename $ADDON_DIR)
    ADDON_FILE=$ADDON_DIR/$ADDON_NAME.txt
    ADDON_REPO=$(cut -d' ' -f2 $ADDON_FILE)
    ADDON_EXISTING_BRANCH=$(cut -d' ' -f3 $ADDON_FILE)

    if [[ "$ADDON_EXISTING_BRANCH" = "master" ]] ; then
      echo "$ADDON_NAME uses master branch. Skipping"
      echo "$ADDON_NAME $ADDON_REPO $ADDON_EXISTING_BRANCH branch used in repo-binary-addons. Review" >> $FAIL_FILE
      continue
    fi

    # Extract Owner name from ADDON_REPO URL
    # Used for Github API requests - default branch check and set
    [[ $ADDON_REPO =~ ^https://github.com/(.*)/$ADDON_NAME$ ]]
    ADDON_REPO_OWNER=${BASH_REMATCH[1]}

    if [ "$CLEAN" = true ] ; then
      rm -rf $PWD/$ADDON_NAME
    fi

    if [ ! -d $PWD/$ADDON_NAME ] ; then
      git clone $ADDON_REPO &>/dev/null
    fi

    ## Check if remote has NEW_BRANCH already
    BRANCH_TEST=$( { cd $PWD/$ADDON_NAME && git ls-remote $ADDON_REPO $NEW_BRANCH | wc -l; } )

    # wc -l returns 1 if a branch exists from git ls-remote call
    # only continue if 0 as a branch does not exist
    if [[ "$BRANCH_TEST" -eq 0 ]] ; then

      CHECKOUT=$( { cd $PWD/$ADDON_NAME && git checkout $OLD_BRANCH; } 2>&1 >/dev/null )

      # Error out if checkout failed
      case $CHECKOUT in
        error:*) echo Failed to checkout $OLD_BRANCH branch. Skipping $ADDON_NAME.
                 echo $ADDON_NAME $ADDON_REPO $CHECKOUT >> $FAIL_FILE
                 remove_repo_addon
                 continue
                  ;;
      esac
      unset CHECKOUT

      ## Version Update Commit
      ADDON_XML_FILE=$PWD/$ADDON_NAME/$ADDON_NAME/addon.xml.in
      ADDON_XML_FILE_BACKUP=$PWD/$ADDON_NAME/$ADDON_NAME/addon.xml.ine

      # Macos cant deal with sed -i. was unable to get a sed_cmd variable to work with
      # sed -i '', so just use -ie and remove backup file created before commit
      sed -ie '2,$s|\(\s*version="\).*\(["].*\)|\1'${VERSION}'\2|' $ADDON_XML_FILE
      rm_file $ADDON_XML_FILE_BACKUP

      # Not sure if we need to safety check commit
      COMMIT=$( { cd $PWD/$ADDON_NAME && git add --all && git commit -m '['${NEW_BRANCH}'] Version bump '${VERSION} ; } )

      ## Jenkinsfile Update Commit
      JENKINS_FILE=$PWD/$ADDON_NAME/Jenkinsfile
      JENKINS_FILE_BACKUP=$PWD/$ADDON_NAME/Jenkinsfilee

      # Macos cant deal with sed -i. was unable to get a sed_cmd variable to work with
      # sed -i '', so just use -ie and remove backup file created before commit
      sed -ie "s|${ADDON_EXISTING_BRANCH}|${NEW_BRANCH}|g" $JENKINS_FILE
      rm_file $JENKINS_FILE_BACKUP

      ## azure-pipelines.yml Update Commit
      AZUREPIPELINE_FILE=$PWD/$ADDON_NAME/azure-pipelines.yml
      AZUREPIPELINE_FILE_BACKUP=$PWD/$ADDON_NAME/azure-pipelines.ymle

      # Macos cant deal with sed -i. was unable to get a sed_cmd variable to work with
      # sed -i '', so just use -ie and remove backup file created before commit
      sed -ie "s|- ${AZURE_PIPELINE_REMOVE_BRANCH}|- ${NEW_BRANCH}|g" $AZUREPIPELINE_FILE
      rm_file $AZUREPIPELINE_FILE_BACKUP

      ## azure-pipelines.yml Update Commit
      # If an addon changes the default xbmc branch (eg to a Named branch rather than master)
      # we revert back to master for latest
      GITHUB_BUILD_FILE=$PWD/$ADDON_NAME/.github/workflows/build.yml
      GITHUB_BUILD_FILE_BACKUP=$PWD/$ADDON_NAME/.github/workflows/build.ymle

      # Macos cant deal with sed -i. was unable to get a sed_cmd variable to work with
      # sed -i '', so just use -ie and remove backup file created before commit
      sed -ie "s|ref: ${ADDON_EXISTING_BRANCH}|ref: master|g" $GITHUB_BUILD_FILE
      rm_file $GITHUB_BUILD_FILE_BACKUP

      # Not sure if we need to safety check commit
      COMMIT=$( { cd $PWD/$ADDON_NAME && git add --all && git commit -m '['${NEW_BRANCH}'] CI files branch update to '${NEW_BRANCH} ; } )

      if [[ -z "$DRYRUN" ]] ; then
        PUSH_BRANCH=$( { cd $PWD/$ADDON_NAME && git push origin $OLD_BRANCH:$NEW_BRANCH ; } 2>&1 >/dev/null )

        case "$PUSH_BRANCH" in
          *Permission*) echo Failed to push to repo $ADDON_REPO. Permission error. Skipping $ADDON_NAME.
                        echo $ADDON_NAME $ADDON_REPO $PUSH_BRANCH >> $FAIL_FILE
                        remove_repo_addon
                        continue
                        ;;
        esac

        ADDON_SUCCESS=true
        unset PUSH_BRANCH

        # Set default branch to NEW_BRANCH
        # Requires a PAT token for Github API requests
        if [[ ! -z "$PAT_TOKEN" ]] ; then
          set_default_branch
        fi
      else
        # Dry run doesnt attempt to push to repo. Assume success for testing purposes
        ADDON_SUCCESS=true
      fi
    else
      echo "$NEW_BRANCH already exists for $ADDON_NAME"
      echo $ADDON_NAME $ADDON_REPO $NEW_BRANCH already exists >> $FAIL_FILE
      ADDON_SUCCESS=true

      if [[ -z "$DRYRUN" ]] ; then
        # Check if default branch for addon is the NEW_BRANCH, update if it isnt
        # Requires a PAT token for Github API requests
        if [[ ! -z "$PAT_TOKEN" ]] ; then
          GH_API_RESPONSE=$( { curl -H "Accept: application/vnd.github+json" -H "Authorization: token $PAT_TOKEN" https://api.github.com/repos/$ADDON_REPO_OWNER/$ADDON_NAME -o $ADDON_GH_JSON_RESPONSE_FILE; } )
          GH_DEFAULT_BRANCH=$( { grep -o '"default_branch": *"[^"]*"' $ADDON_GH_JSON_RESPONSE_FILE | grep -o '"[^"]*"$' | tr -d '"'; } )

          if [[ "$NEW_BRANCH" != "$GH_DEFAULT_BRANCH" ]] ; then     
            set_default_branch
          fi
        fi
      fi
    fi

    # cleanup API request/response files
    # dont remove if Dry run to allow viewing of request file
    if [ -f $ADDON_GH_JSON_REQUEST_FILE ]; then
      if [[ -z "$DRYRUN" ]] ; then
        rm_file $ADDON_GH_JSON_REQUEST_FILE
      fi
    fi
    rm_file $ADDON_GH_JSON_RESPONSE_FILE

    # Update branch in each addon that we have been able to push successfully to
    # and push to NEW_BRANCH for REPO_BINARYADDONS
    # We also add any addons that already have a NEW_BRANCH

    if [ "$ADDON_SUCCESS" = true ] ; then
      echo "Updating $ADDON_NAME branch from $ADDON_EXISTING_BRANCH to $NEW_BRANCH in repo-binary-addons"

      ADDON_FILE_BACKUP=$ADDON_FILE
      ADDON_FILE_BACKUP+=e

      sed -ie "s|${ADDON_EXISTING_BRANCH}|${NEW_BRANCH}|g" $ADDON_FILE

      # Macos cant deal with sed -i. was unable to get a sed_cmd variable to work with
      # sed -i '', so just use -ie and remove backup file created before commit
      rm_file $ADDON_FILE_BACKUP

      # Not sure if we need to safety check commit
      COMMIT=$( { cd $PWD/repo-binary-addons && git add --all && git commit -m '['${NEW_BRANCH}'] '${ADDON_NAME}' change branch to '${NEW_BRANCH} ; } )

    else
      echo "Removing $ADDON_DIR. Not able to update for $NEW_BRANCH"
      remove_repo_addon
    fi
  fi
done

if [[ -z "$DRYRUN" ]] ; then
  PUSH_BRANCH=$( { cd $PWD/repo-binary-addons && git push origin $OLD_BRANCH:$NEW_BRANCH ; } 2>&1 >/dev/null )

  case "$PUSH_BRANCH" in
    *Permission*) echo Failed to push to repo $REPO_BINARYADDONS. Permission error.
                  ;;
  esac
fi
