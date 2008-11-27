rm -rf html;  
mkdir -p html/Core;
IFS="
"
echo "<html><head></head><body><h1>Perl-Bootloader documentation page</h1><br>" > html/index.html
for line in `find ../src/ -type f| grep -v '.svn' | sed 's:^../src/\(.*\).pm$:\1:'`; do
    echo "pod2html --infile=../src/${line}.pm --outfile=html/${line}.html";
    pod2html --infile=../src/${line}.pm --outfile=html/${line}.html
    echo "<a href=\"$line.html\">$line</a><br>" >> html/index.html
done

    echo "</body></html>" >> html/index.html
