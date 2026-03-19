import ApexCharts from 'apexcharts';

// ===== chartOne
const chart01 = () => {
    const chartOneOptions = {
    series: [
        {
        name: 'Product One',
        data: [23, 11, 22, 27, 13, 22, 37, 21, 44, 22, 30, 45],
        },

        {
        name: 'Product Two',
        data: [30, 25, 36, 30, 45, 35, 64, 52, 59, 36, 39, 51],
        },
    ],
    legend: {
        show: true,
        position: 'top',
        horizontalAlign: 'left',
    },
    colors: ['#3056D3', '#13C296'],
    chart: {
        height: 240,
        type: 'line',
        dropShadow: {
        enabled: true,
        color: '#623CEA',
        top: 10,
        blur: 4,
        left: 0,
        opacity: 0.1,
        },

        toolbar: {
        show: false,
        },
    },
    responsive: [
        {
        breakpoint: 1024,
        options: {
            chart: {
            height: 240,
            },
        },
        },
        {
        breakpoint: 1366,
        options: {
            chart: {
            height: 240,
            },
        },
        },
    ],
    stroke: {
        width: [4, 4],
        curve: 'smooth',
    },

    markers: {
        size: 0,
    },
    labels: {
        show: false,
        position: 'top',
    },
    grid: {
        xaxis: {
        lines: {
            show: true,
        },
        },
        yaxis: {
        lines: {
            show: false,
        },
        },
    },
    xaxis: {
        type: 'category',
        categories: [
        'Sep',
        'Oct',
        'Nov',
        'Dec',
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        ],
        axisBorder: {
        show: false,
        },
        axisTicks: {
        show: false,
        },
    },
    yaxis: {
        title: {
        style: {
            fontSize: '0px',
        },
        },
        min: 0,
        max: 100,

        labels: {
        style: {
            colors: ['transparent'],
        },
        },
    },
    };

    const chartSelector = document.querySelectorAll('#chartOne');

    if(chartSelector.length) {
        const chartOne = new ApexCharts(
        document.querySelector('#chartOne'),
        chartOneOptions
        );
        chartOne.render();
    }
};

export default chart01;
