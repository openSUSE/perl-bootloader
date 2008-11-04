rm -rf html;  
mkdir -p html/Core;
IFS="
"
for line in `find ../src/ -type f| grep -v '.svn' | sed 's:^../src/\(.*\).pm$:\1:'`; do
    echo "pod2html --infile=../src/${line}.pm --outfile=html/${line}.html";
    pod2html --infile=../src/${line}.pm --outfile=html/${line}.html
done
