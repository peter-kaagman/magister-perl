#! /bin/bash
echo "# magister-perl" >> README.md
git init
git add .
git commit -m "first commit"
git branch -M main
git remote add origin git@github.com:peter-kaagman/magister-perl.git
git push -u origin main