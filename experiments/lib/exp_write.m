function exp_write(file, T)
% Writes table T to the run's outputs as file (params.csv, wv.csv or fit.csv). run.py then
% checks its columns and units against experiments/README.md. NaN is written as an empty field

% writetable would write NaN as "NaN"; format each cell so a missing value stays empty
n = height(T);
cells = strings(n, width(T));
for c = 1:width(T)
    col = T.(c);
    if isnumeric(col)
        s = compose("%.10g", col);
        s(isnan(col)) = "";
    else
        s = string(col);
        quote = contains(s, ["," """" newline]); % CSV: quote the field, doubling its quotes
        s(quote) = """" + replace(s(quote), """", """""") + """";
    end
    cells(:, c) = s;
end
writelines([strjoin(string(T.Properties.VariableNames), ","); join(cells, ",", 2)], ...
           fullfile(getenv("EXP_OUT"), file));
end
