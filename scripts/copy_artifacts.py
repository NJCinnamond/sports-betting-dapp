import os
import shutil

ARTIFACTS_REL_PATH = "../artifacts"
FRONTEND_REL_PATH = "../../sports-betting-ui/sports-betting-ui/artifacts"


def copy_folders_to_front_end(src, dest):
    if os.path.exists(dest):
        shutil.rmtree(dest)
    shutil.copytree(src, dest)


def main():
    copy_folders_to_front_end(ARTIFACTS_REL_PATH, FRONTEND_REL_PATH)
    print("Front end repo updated")


main()
