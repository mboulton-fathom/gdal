#ifndef GDAL_PROGRAM_NAME
#error must define 'GDAL_PROGRAM_NAME' at compile time
#endif

extern int run_program(char *const gdal_program_name, int argc, char **argv);

int main(int argc, char **argv)
{
    return run_program(const_cast<char *const>(GDAL_PROGRAM_NAME), argc, argv);
}
